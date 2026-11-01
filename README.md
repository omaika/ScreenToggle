# ScreenToggle

A tiny macOS menu bar app to disconnect and reconnect displays — for example, turn off the
built-in screen while using an external monitor (like BetterDisplay's "Connect this display").

## Download
Grab `ScreenToggle-vX.Y.Z.zip` from [Releases](https://github.com/omaika/ScreenToggle/releases)
(universal binary, macOS 13+), unzip it and move `ScreenToggle.app` to `/Applications`.
The app is ad-hoc signed, not notarized, so macOS blocks the first launch. Allow it once with:

    xattr -dr com.apple.quarantine /Applications/ScreenToggle.app

## Releasing
Push a version tag; GitHub Actions builds the app and publishes the release:

    git tag v1.0.0 && git push origin v1.0.0

## Build & run
    xcode-select --install     # if you don't have the Command Line Tools yet
    ./build.sh
    open ScreenToggle.app

A display icon appears in the menu bar. A checkmark means the display is connected; click a
display to disconnect or reconnect it. Enable "Launch at Login" from the same menu.

## CLI
    ScreenToggle.app/Contents/MacOS/ScreenToggle list
    ScreenToggle.app/Contents/MacOS/ScreenToggle disconnect <id>
    ScreenToggle.app/Contents/MacOS/ScreenToggle connect <id>

## Safety
- The last active display can never be disconnected.
- Changes apply to the current login session only; logging out or rebooting restores all displays.
- Quitting the app reconnects every display it turned off; "Reconnect All" reconnects everything.
- Unplugging the external monitor while the built-in screen is off: the app turns the built-in
  screen back on after ~1 second (retrying up to 5 times).
- Waking from sleep/hibernation (e.g. after the battery ran low) with no active display: the app
  turns one back on as well.
- Battery dies or power is lost and the Mac shuts down: the next boot restores all displays.
- Global hot key **⌃⌥⌘K** (Control + Option + Command + K) = "Reconnect All". It works even on a
  black screen, e.g. when the external monitor loses power but macOS still reports it as connected,
  so the app cannot detect it on its own.
- Still black? Run `... connect <id>` over SSH, or reboot.
- The automatic recovery only works while the app is running in the menu bar, so keep
  "Launch at Login" on.

## Notes
Uses the private CoreGraphics function `CGSConfigureDisplayEnabled` (there is no public API for
this, and similar tools use the same technique), so a future macOS release may break it.
Tested on macOS 26 (Darwin 25).
