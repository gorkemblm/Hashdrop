// Renders Resources/AppIcon.icns (and docs/icon.png for the README): a white "#" on a Discord-ish blurple squircle.
// Usage: swift scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024

    // macOS icon grid: 824pt artwork centered in a 1024pt canvas.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.35, green: 0.32, blue: 0.95, alpha: 1).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(calibratedRed: 0.49, green: 0.47, blue: 1.0, alpha: 1),
               ending: NSColor(calibratedRed: 0.27, green: 0.21, blue: 0.86, alpha: 1))!
        .draw(in: path, angle: -90)

    // Soft glassy highlight on the upper half.
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(starting: NSColor.white.withAlphaComponent(0.22), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let config = NSImage.SymbolConfiguration(pointSize: 440 * s, weight: .bold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "number", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let size = symbol.size
        let glyphShadow = NSShadow()
        glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        glyphShadow.shadowOffset = NSSize(width: 0, height: -8 * s)
        glyphShadow.shadowBlurRadius = 16 * s
        NSGraphicsContext.saveGraphicsState()
        glyphShadow.set()
        symbol.draw(in: NSRect(x: tile.midX - size.width / 2, y: tile.midY - size.height / 2, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! task.run()
task.waitUntilExit()
try! render(256).write(to: root.appendingPathComponent("docs/icon.png"))
print(task.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")
