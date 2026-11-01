// ScreenToggle — menu bar app to disconnect / reconnect displays (like BetterDisplay's "Connect this display").
// Uses the private CoreGraphics symbol CGSConfigureDisplayEnabled (no public API exists for this).
// Build: ./build.sh     Run: open ScreenToggle.app
// CLI:   ScreenToggle.app/Contents/MacOS/ScreenToggle list | disconnect <id> | connect <id>

import Carbon.HIToolbox
import Cocoa
import CoreGraphics
import ServiceManagement

@_silgen_name("CGSConfigureDisplayEnabled")
func CGSConfigureDisplayEnabled(_ config: CGDisplayConfigRef?, _ display: CGDirectDisplayID, _ enable: Bool) -> CGError

struct DisplayInfo {
    let id: CGDirectDisplayID
    let name: String
    let isActive: Bool
    let isBuiltin: Bool
}

enum DisplayManager {
    private static let namesKey = "knownDisplayNames"

    static func ids(online: Bool) -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        _ = online ? CGGetOnlineDisplayList(0, nil, &count) : CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }
        var list = [CGDirectDisplayID](repeating: 0, count: Int(count))
        _ = online ? CGGetOnlineDisplayList(count, &list, &count) : CGGetActiveDisplayList(count, &list, &count)
        return list.prefix(Int(count)).filter { !isPlaceholder($0) }
    }

    /// When the last real display goes away (e.g. the external monitor is unplugged while the
    /// built-in one is disabled), macOS swaps in an "active" virtual 1920x1080 display with
    /// vendor 'unkn' and model 'virt' that shows nothing. It must not count as a real display.
    static func isPlaceholder(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayVendorNumber(id) == 0x756e_6b6e // 'unkn'
    }

    static func list() -> [DisplayInfo] {
        let active = Set(ids(online: false))
        var cache = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String] ?? [:]
        var screenNames: [CGDirectDisplayID: String] = [:]
        for s in NSScreen.screens {
            if let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                screenNames[n.uint32Value] = s.localizedName
            }
        }
        var result: [DisplayInfo] = []
        for id in ids(online: true) {
            // Mirrored displays are not "active" but are still connected: treat as active.
            let mirrored = CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay
            let isActive = active.contains(id) || mirrored
            if let n = screenNames[id] { cache[String(id)] = n }
            let name = screenNames[id] ?? cache[String(id)] ?? "Display \(id)"
            result.append(DisplayInfo(id: id, name: name, isActive: isActive, isBuiltin: CGDisplayIsBuiltin(id) != 0))
        }
        UserDefaults.standard.set(cache, forKey: namesKey)

        // A disabled display may vanish from the online list entirely, so we remember
        // the ones we disconnected and keep showing them (unchecked) so they can be reconnected.
        var parked = parkedDisplays()
        let seenActive = Set(result.filter { $0.isActive }.map { String($0.id) })
        let seenAll = Set(result.map { String($0.id) })
        for key in parked.keys where seenActive.contains(key) { parked[key] = nil } // came back by itself
        for (key, name) in parked where !seenAll.contains(key) {
            if let id = UInt32(key) {
                result.append(DisplayInfo(id: id, name: name, isActive: false, isBuiltin: false))
            }
        }
        UserDefaults.standard.set(parked, forKey: parkedKey)
        return result
    }

    private static let parkedKey = "disconnectedDisplays"
    private static func parkedDisplays() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: parkedKey) as? [String: String] ?? [:]
    }

    @discardableResult
    static func setEnabled(_ id: CGDirectDisplayID, _ enable: Bool) -> Bool {
        var name = "Display \(id)"
        if !enable {
            // Safety: never disconnect the last remaining active display.
            let all = list()
            if all.filter({ $0.isActive }).count <= 1 { return false }
            name = all.first { $0.id == id }?.name ?? name
        }
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success else { NSLog("ScreenToggle: begin failed \(begin.rawValue)"); return false }
        let err = CGSConfigureDisplayEnabled(config, id, enable)
        guard err == .success else {
            NSLog("ScreenToggle: CGSConfigureDisplayEnabled(\(id), \(enable)) failed \(err.rawValue)")
            CGCancelDisplayConfiguration(config)
            return false
        }
        // .forSession: the change is reverted at logout/reboot, so you can't get stuck.
        let done = CGCompleteDisplayConfiguration(config, .forSession)
        guard done == .success else { NSLog("ScreenToggle: complete failed \(done.rawValue)"); return false }

        var parked = parkedDisplays()
        if enable { parked[String(id)] = nil } else { parked[String(id)] = name }
        UserDefaults.standard.set(parked, forKey: parkedKey)
        return true
    }

    /// If no display is active any more (e.g. the external screen was unplugged while the
    /// built-in one was disconnected), turn one back on — built-in first — so the Mac isn't left black.
    /// Returns true when nothing needed doing or a display was restored.
    @discardableResult
    static func restoreIfNoActiveDisplay() -> Bool {
        guard ids(online: false).isEmpty else { return true }
        var candidates = Set(parkedDisplays().keys.compactMap { UInt32($0) })
        candidates.formUnion(ids(online: true))
        let ordered = candidates.sorted { CGDisplayIsBuiltin($0) != 0 && CGDisplayIsBuiltin($1) == 0 }
        for id in ordered where setEnabled(id, true) {
            NSLog("ScreenToggle: no active display left, re-enabled \(id)")
            return true
        }
        return false
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var disconnectedByUs = Set<CGDirectDisplayID>()

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Displays")
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Watch for displays being unplugged so we never end up with every screen disabled.
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            guard !flags.contains(.beginConfigurationFlag),
                  flags.contains(.removeFlag) || flags.contains(.disabledFlag) || flags.contains(.addFlag)
            else { return }
            DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.scheduleBlackoutCheck() }
        }, nil)
        scheduleBlackoutCheck()

        // Low-battery hibernation keeps the session, so the built-in can still be off on wake.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            self?.scheduleBlackoutCheck()
        }
        registerReconnectHotKey()
    }

    private var hotKeyRef: EventHotKeyRef?

    /// Global ⌃⌥⌘K = Reconnect All. Escape hatch for when the screen is black but no unplug was
    /// detected (e.g. the external monitor lost power yet still reports as connected).
    /// Carbon hot keys need no Accessibility permission.
    private func registerReconnectHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.reconnectAll() }
            return noErr
        }, 1, &spec, nil, nil)
        let hotKeyID = EventHotKeyID(signature: OSType(0x4444_4953), id: 1) // 'DDIS'
        let err = RegisterEventHotKey(UInt32(kVK_ANSI_K), UInt32(controlKey | optionKey | cmdKey),
                                      hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        if err != noErr { NSLog("ScreenToggle: hot key registration failed \(err)") }
    }

    private var blackoutCheck: DispatchWorkItem?

    /// Debounced: reconfiguration fires several callbacks in a row, and right after an unplug
    /// re-enabling can fail, so check after things settle and retry a few times.
    func scheduleBlackoutCheck(attempt: Int = 0) {
        blackoutCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if !DisplayManager.restoreIfNoActiveDisplay() && attempt < 5 {
                self?.scheduleBlackoutCheck(attempt: attempt + 1)
            }
        }
        blackoutCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func applicationWillTerminate(_ n: Notification) {
        // Restore anything we turned off so quitting never leaves a screen dark.
        for d in DisplayManager.list() where !d.isActive { DisplayManager.setEnabled(d.id, true) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let displays = DisplayManager.list()
        let activeCount = displays.filter { $0.isActive }.count

        for d in displays {
            let item = NSMenuItem(title: d.name + (d.isBuiltin ? " (Built-in)" : ""),
                                  action: #selector(toggle(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(d.id)
            item.state = d.isActive ? .on : .off          // checkmark = connected
            if d.isActive && activeCount <= 1 { item.isEnabled = false } // last display
            menu.addItem(item)
        }
        if displays.isEmpty { menu.addItem(withTitle: "No displays found", action: nil, keyEquivalent: "") }

        menu.addItem(.separator())
        let all = NSMenuItem(title: "Reconnect All", action: #selector(reconnectAll), keyEquivalent: "k")
        all.keyEquivalentModifierMask = [.control, .option, .command] // also a global hot key
        all.target = self
        menu.addItem(all)
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let about = NSMenuItem(title: "About ScreenToggle", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let q = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        q.target = self
        menu.addItem(q)
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        let id = CGDirectDisplayID(sender.tag)
        let wantEnable = sender.state != .on
        if DisplayManager.setEnabled(id, wantEnable) {
            if wantEnable { disconnectedByUs.remove(id) } else { disconnectedByUs.insert(id) }
        } else {
            NSSound.beep()
        }
    }

    @objc func reconnectAll() {
        for d in DisplayManager.list() where !d.isActive { DisplayManager.setEnabled(d.id, true) }
        disconnectedByUs.removeAll()
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("ScreenToggle: launch-at-login failed: \(error)")
            NSSound.beep()
        }
    }

    /// Standard About panel: icon, name, "Version <CFBundleShortVersionString> (<CFBundleVersion>)".
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true) // menu bar apps aren't frontmost; bring the panel forward
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "github.com/omaika/ScreenToggle"),
        ])
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Entry point (CLI mode if arguments are given)
let args = CommandLine.arguments
if args.count >= 2 {
    switch args[1] {
    case "list":
        for d in DisplayManager.list() {
            print("\(d.id)\t\(d.isActive ? "connected" : "disconnected")\t\(d.name)\(d.isBuiltin ? " (built-in)" : "")")
        }
    case "disconnect", "connect":
        guard args.count >= 3, let id = UInt32(args[2]) else { print("usage: \(args[0]) \(args[1]) <id>"); exit(2) }
        let ok = DisplayManager.setEnabled(id, args[1] == "connect")
        print(ok ? "ok" : "failed (last display, bad id, or API unsupported on this macOS)")
        exit(ok ? 0 : 1)
    default:
        print("usage: \(args[0]) [list | disconnect <id> | connect <id>]"); exit(2)
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
