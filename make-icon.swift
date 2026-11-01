// Draws the app icon and writes AppIcon.icns.   Run: swift make-icon.swift
// Shapes are drawn by hand (SF Symbols may not be used in app icons).

import Cocoa

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // Background: macOS-style rounded square (824pt artwork inside a 1024 canvas) with a blue gradient.
    let bg = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 0.33, green: 0.56, blue: 1.0, alpha: 1),
               ending: NSColor(srgbRed: 0.27, green: 0.20, blue: 0.80, alpha: 1))!.draw(in: bg, angle: -90)

    // Monitor: white bezel, dark screen, stand.
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 222, y: 400, width: 580, height: 380), xRadius: 44, yRadius: 44).fill()
    NSBezierPath(roundedRect: NSRect(x: 462, y: 318, width: 100, height: 90), xRadius: 8, yRadius: 8).fill()
    NSBezierPath(roundedRect: NSRect(x: 352, y: 290, width: 320, height: 46), xRadius: 23, yRadius: 23).fill()
    NSColor(srgbRed: 0.10, green: 0.12, blue: 0.22, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 252, y: 430, width: 520, height: 320), xRadius: 22, yRadius: 22).fill()

    // Toggle switch on the screen: green track, white knob on the right (= on).
    NSColor(srgbRed: 0.20, green: 0.80, blue: 0.40, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 362, y: 530, width: 300, height: 140), xRadius: 70, yRadius: 70).fill()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 532, y: 540, width: 120, height: 120)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "AppIcon.icns"]
try! p.run(); p.waitUntilExit()
try? fm.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "Wrote AppIcon.icns" : "iconutil failed")
