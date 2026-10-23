import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders the README GIFs from the real SwiftUI views, using made-up channels:
///     Hashdrop --render-demo <output-dir>
/// No screen recording permission needed; nothing is sent and the user's settings aren't touched.
@MainActor
final class DemoRenderer: NSObject, NSApplicationDelegate {
    private let outputDirectory: URL

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                try await renderSendDemo()
                try await renderChannelDemo()
                try await renderLinksDemo()
                try await renderHistoryImage()
                print("Rendered demo images to \(outputDirectory.path)")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Demo render failed: \(error)\n".utf8))
                exit(1)
            }
        }
    }

    // MARK: - Demo data

    private static let now = Date()

    private static var settings: AppSettings {
        var s = AppSettings()
        s.channels = [
            Channel(name: "news", server: "Gaming Hub", method: .webhook, webhookURL: "https://discord.com/api/webhooks/1/demo", lastUsed: now.addingTimeInterval(-60)),
            Channel(name: "memes", server: "Friends", method: .app, channelLink: "https://discord.com/channels/1/2", lastUsed: now.addingTimeInterval(-3_600)),
            Channel(name: "dev-links", server: "Side Project", method: .webhook, webhookURL: "https://discord.com/api/webhooks/2/demo", lastUsed: now.addingTimeInterval(-7_200)),
            Channel(name: "music", server: "Friends", method: .app, channelLink: "https://discord.com/channels/1/3", lastUsed: now.addingTimeInterval(-86_400)),
            Channel(name: "general", server: "Gaming Hub", method: .app, channelLink: "https://discord.com/channels/4/5"),
        ]
        return s
    }

    private static let clipboardLink = "https://x.com/hashdrop_app/status/1851234567890123456"
    private static let recentLinks = [
        "https://www.youtube.com/watch?v=hashdrop-demo",
        "https://github.com/gorkemblm/hashdrop",
        "https://news.ycombinator.com/item?id=41000000",
    ]

    private func makeComposer(recentLinks: [String] = []) -> ComposerModel {
        ComposerModel(
            clip: ClipContent(text: Self.clipboardLink, image: nil),
            recentLinks: recentLinks,
            store: SettingsStore(inMemory: Self.settings)
        )
    }

    // MARK: - Scenes

    private func renderSendDemo() async throws {
        let model = makeComposer()
        let panel = Snapshotter(ComposerView(model: model))
        let stage = Stage()
        var gif = GIF()

        gif.add(stage.compose(caption: "Copy a link, press ⌥⇧D"), delay: 1.1)
        let first = await panel.snap(settle: 0.5)
        for step in 1...5 {
            let t = CGFloat(step) / 5
            gif.add(stage.compose(panel: .init(image: first, radius: 24, placement: .center, scale: 0.94 + 0.06 * t, alpha: t), caption: "⌥⇧D"), delay: 0.035)
        }
        gif.add(stage.compose(panel: .init(image: first, radius: 24, placement: .center), caption: "⌥⇧D"), delay: 0.9)

        for (delta, key) in [(1, "↓"), (1, "↓"), (-1, "↑")] {
            model.move(delta)
            let image = await panel.snap(settle: 0.3)
            gif.add(stage.compose(panel: .init(image: image, radius: 24, placement: .center), caption: key), delay: 0.55)
        }

        let comment = "this is wild 😂"
        var typed = ""
        for character in comment {
            typed.append(character)
            model.input = typed
            let image = await panel.snap()
            gif.add(stage.compose(panel: .init(image: image, radius: 24, placement: .center), caption: "Add a comment (optional)"), delay: 0.06)
        }
        let typedImage = await panel.snap()
        gif.add(stage.compose(panel: .init(image: typedImage, radius: 24, placement: .center), caption: "Add a comment (optional)"), delay: 0.7)

        try await addHoldAndSend(model: model, panel: panel, stage: stage, gif: &gif, channel: "memes")
        try gif.write(to: outputDirectory.appendingPathComponent("demo-send.gif"))
    }

    private func renderChannelDemo() async throws {
        let model = makeComposer()
        let panel = Snapshotter(ComposerView(model: model))
        let stage = Stage()
        var gif = GIF()

        let start = await panel.snap(settle: 0.5)
        gif.add(stage.compose(panel: .init(image: start, radius: 24, placement: .center), caption: "Type #name to jump to a channel"), delay: 0.9)

        for prefix in ["#", "#d", "#de", "#dev"] {
            model.input = prefix
            let image = await panel.snap(settle: 0.3)
            gif.add(stage.compose(panel: .init(image: image, radius: 24, placement: .center), caption: "Type #name to jump to a channel"), delay: 0.22)
        }
        let filtered = await panel.snap()
        gif.add(stage.compose(panel: .init(image: filtered, radius: 24, placement: .center), caption: "Type #name to jump to a channel"), delay: 0.6)

        model.returnDown()
        model.returnUp()
        let picked = await panel.snap(settle: 0.4)
        gif.add(stage.compose(panel: .init(image: picked, radius: 24, placement: .center), caption: "⏎  picks it"), delay: 0.9)

        var typed = ""
        for character in "worth a read" {
            typed.append(character)
            model.input = typed
            let image = await panel.snap()
            gif.add(stage.compose(panel: .init(image: image, radius: 24, placement: .center), caption: "Add a comment (optional)"), delay: 0.06)
        }
        let typedImage = await panel.snap()
        gif.add(stage.compose(panel: .init(image: typedImage, radius: 24, placement: .center), caption: "Add a comment (optional)"), delay: 0.6)

        try await addHoldAndSend(model: model, panel: panel, stage: stage, gif: &gif, channel: "dev-links")
        try gif.write(to: outputDirectory.appendingPathComponent("demo-channel.gif"))
    }

    private func renderLinksDemo() async throws {
        let model = makeComposer(recentLinks: Self.recentLinks)
        let panel = Snapshotter(ComposerView(model: model))
        let stage = Stage()
        var gif = GIF()

        let start = await panel.snap(settle: 0.5)
        gif.add(stage.compose(panel: .init(image: start, radius: 24, placement: .center), caption: "Your last copied links, one keystroke away"), delay: 1.2)

        for (index, key) in [(1, "⌘→"), (2, "⌘→"), (3, "⌘→"), (2, "⌘←"), (1, "⌘←")] {
            model.sourceIndex = index
            let image = await panel.snap(settle: 0.25)
            gif.add(stage.compose(panel: .init(image: image, radius: 24, placement: .center), caption: key), delay: 0.7)
        }
        try gif.write(to: outputDirectory.appendingPathComponent("demo-links.gif"))
    }

    private func renderHistoryImage() async throws {
        let entries = [
            HistoryEntry(date: Self.now.addingTimeInterval(-30), channelName: "memes", server: "Friends", text: "this is wild 😂\n\(Self.clipboardLink)", hasImage: false),
            HistoryEntry(date: Self.now.addingTimeInterval(-900), channelName: "dev-links", server: "Side Project", text: "worth a read\nhttps://news.ycombinator.com/item?id=41000000", hasImage: false),
            HistoryEntry(date: Self.now.addingTimeInterval(-5_400), channelName: "news", server: "Gaming Hub", text: "https://www.youtube.com/watch?v=hashdrop-demo", hasImage: false),
            HistoryEntry(date: Self.now.addingTimeInterval(-20_000), channelName: "music", server: "Friends", text: "", hasImage: true),
        ]
        let view = HistoryView(
            history: HistoryStore(inMemory: entries),
            store: SettingsStore(inMemory: Self.settings),
            clipboard: ClipboardWatcher(),
            onSendClipboard: {}, onOpenSettings: {}, onQuit: {}
        )
        let panel = Snapshotter(view)
        let image = await panel.snap(settle: 0.8) // rows cascade in
        let stage = Stage(size: CGSize(width: 860, height: 520))
        let frame = stage.compose(panel: .init(image: image, radius: 22, placement: .belowMenuIcon), menuIconHighlighted: true, caption: "Click the menu bar icon for recent sends")
        try GIF.writePNG(frame, to: outputDirectory.appendingPathComponent("history.png"))
    }

    private func addHoldAndSend(model: ComposerModel, panel: Snapshotter, stage: Stage, gif: inout GIF, channel: String) async throws {
        let steps = 9
        for step in 0...steps {
            model.holdProgress = Double(step) / Double(steps)
            let image = await panel.snap(settle: step == 0 ? 0.25 : 0.03)
            gif.add(stage.compose(panel: .init(image: image, radius: 24, placement: .center), caption: "Hold ⏎ to send"), delay: 0.055)
        }
        let full = await panel.snap()
        for step in 1...3 {
            let alpha = 1 - CGFloat(step) / 3
            gif.add(stage.compose(panel: .init(image: full, radius: 24, placement: .center, scale: 1 - 0.03 * CGFloat(step) / 3, alpha: alpha), caption: "Hold ⏎ to send"), delay: 0.04)
        }

        let toast = await Snapshotter(ToastView(title: "Sent to #\(channel)", detail: nil, style: .success)).snap(settle: 0.6)
        for step in 1...4 {
            let t = CGFloat(step) / 4
            gif.add(stage.compose(toast: .init(image: toast, radius: 18, placement: .belowMenuIcon, offsetY: 10 * (1 - t), alpha: t), menuIconFlash: true, caption: "Sent ✓"), delay: 0.04)
        }
        gif.add(stage.compose(toast: .init(image: toast, radius: 18, placement: .belowMenuIcon), menuIconFlash: true, caption: "Sent ✓"), delay: 1.6)
        for step in 1...3 {
            gif.add(stage.compose(toast: .init(image: toast, radius: 18, placement: .belowMenuIcon, alpha: 1 - CGFloat(step) / 3), caption: "Sent ✓"), delay: 0.05)
        }
        gif.add(stage.compose(), delay: 0.6)
    }
}

// MARK: - Offscreen view snapshots

@MainActor
private final class Snapshotter {
    private let window: NSWindow
    private let host: NSHostingView<AnyView>

    init(_ view: some View) {
        host = NSHostingView(rootView: AnyView(view.environment(\.stillRender, true).environment(\.colorScheme, .dark)))
        window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 10, height: 10), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFrontRegardless()
    }

    /// Lets SwiftUI apply pending state (and finish animations), then draws the view into a bitmap at 2x.
    func snap(settle: Double = 0.06) async -> CGImage {
        try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000))
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let bounds = host.bounds
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = bounds.size
        host.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage!
    }
}

// MARK: - Backdrop + compositing

private struct Layer {
    enum Placement { case center, belowMenuIcon }

    var image: CGImage
    var radius: CGFloat
    var placement: Placement
    var scale: CGFloat = 1
    var offsetY: CGFloat = 0
    var alpha: CGFloat = 1
}

@MainActor
private final class Stage {
    let size: CGSize
    private let scale: CGFloat = 2
    private let wallpaper: CGImage
    private let blurred: CGImage
    private let menuBarHeight: CGFloat = 30
    private var menuIconX: CGFloat { size.width - 172 }

    init(size: CGSize = CGSize(width: 860, height: 640)) {
        self.size = size
        wallpaper = Stage.makeWallpaper(size: size, scale: scale)
        let ci = CIImage(cgImage: wallpaper)
        let blur = ci.clampedToExtent().applyingGaussianBlur(sigma: 36).cropped(to: ci.extent)
        blurred = CIContext().createCGImage(blur, from: ci.extent)!
    }

    func compose(panel: Layer? = nil, toast: Layer? = nil, menuIconHighlighted: Bool = false, menuIconFlash: Bool = false, caption: String? = nil) -> CGImage {
        let ctx = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.scaleBy(x: scale, y: scale)
        let full = CGRect(origin: .zero, size: size)
        ctx.draw(wallpaper, in: full)
        drawMenuBar(ctx, highlighted: menuIconHighlighted, flash: menuIconFlash)
        for layer in [panel, toast].compactMap({ $0 }) {
            draw(layer, in: ctx)
        }
        if let caption { drawCaption(caption, in: ctx) }
        return ctx.makeImage()!
    }

    private func frame(for layer: Layer) -> CGRect {
        let w = CGFloat(layer.image.width) / scale, h = CGFloat(layer.image.height) / scale
        switch layer.placement {
        case .center:
            return CGRect(x: (size.width - w) / 2, y: (size.height - menuBarHeight - h) / 2 + 6, width: w, height: h).integral
        case .belowMenuIcon:
            let x = min(max(menuIconX - w / 2, 10), size.width - w - 10)
            return CGRect(x: x, y: size.height - menuBarHeight - 8 - h + layer.offsetY, width: w, height: h).integral
        }
    }

    private func draw(_ layer: Layer, in ctx: CGContext) {
        let rect = frame(for: layer)
        ctx.saveGState()
        ctx.setAlpha(layer.alpha)
        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.scaleBy(x: layer.scale, y: layer.scale)
        ctx.translateBy(x: -rect.midX, y: -rect.midY)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)

        let path = CGPath(roundedRect: rect, cornerWidth: layer.radius, cornerHeight: layer.radius, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: CGColor(gray: 0, alpha: 0.5))
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()

        // Frosted glass: the blurred wallpaper shows through the panel's translucent fill.
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(blurred, in: CGRect(origin: .zero, size: size))
        ctx.restoreGState()

        ctx.draw(layer.image, in: rect)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private func drawMenuBar(_ ctx: CGContext, highlighted: Bool, flash: Bool) {
        let bar = CGRect(x: 0, y: size.height - menuBarHeight, width: size.width, height: menuBarHeight)
        ctx.saveGState()
        ctx.clip(to: bar)
        ctx.draw(blurred, in: CGRect(origin: .zero, size: size))
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.35))
        ctx.fill(bar)
        ctx.restoreGState()

        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns

        if highlighted {
            NSColor.white.withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: NSRect(x: menuIconX - 16, y: bar.minY + 3, width: 32, height: menuBarHeight - 6), xRadius: 6, yRadius: 6).fill()
        }
        let iconName = flash ? "checkmark.circle.fill" : "number"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold).applying(.init(paletteColors: [.white]))
        if let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            icon.draw(in: NSRect(x: menuIconX - icon.size.width / 2, y: bar.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height))
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]
        let time = "Wed 9:41" as NSString
        let tsize = time.size(withAttributes: attrs)
        let timeX = size.width - tsize.width - 14
        time.draw(at: NSPoint(x: timeX, y: bar.midY - tsize.height / 2), withAttributes: attrs)
        var x = timeX - 14
        for name in ["battery.75percent", "wifi"] {
            if let icon = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                x -= icon.size.width
                icon.draw(in: NSRect(x: x, y: bar.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height))
                x -= 14
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Keystroke / step caption pill along the bottom.
    private func drawCaption(_ text: String, in ctx: CGContext) {
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white]
        let string = text as NSString
        let tsize = string.size(withAttributes: attrs)
        let pill = NSRect(x: (size.width - tsize.width) / 2 - 16, y: 22, width: tsize.width + 32, height: tsize.height + 14)
        NSColor.black.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        string.draw(at: NSPoint(x: pill.minX + 16, y: pill.minY + 7), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Abstract dark gradient with soft color blobs — no third-party wallpaper needed.
    private static func makeWallpaper(size: CGSize, scale: CGFloat) -> CGImage {
        let ctx = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.scaleBy(x: scale, y: scale)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let base = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.07, green: 0.06, blue: 0.16, alpha: 1),
            CGColor(red: 0.13, green: 0.08, blue: 0.24, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(base, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        let blobs: [(CGPoint, CGFloat, CGColor)] = [
            (CGPoint(x: size.width * 0.18, y: size.height * 0.72), 320, CGColor(red: 0.42, green: 0.36, blue: 1.0, alpha: 0.75)),
            (CGPoint(x: size.width * 0.85, y: size.height * 0.25), 360, CGColor(red: 0.95, green: 0.35, blue: 0.65, alpha: 0.55)),
            (CGPoint(x: size.width * 0.6, y: size.height * 0.95), 260, CGColor(red: 0.2, green: 0.7, blue: 0.95, alpha: 0.45)),
            (CGPoint(x: size.width * 0.35, y: size.height * 0.05), 280, CGColor(red: 0.3, green: 0.25, blue: 0.85, alpha: 0.5)),
        ]
        for (center, radius, color) in blobs {
            let gradient = CGGradient(colorsSpace: space, colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }
        return ctx.makeImage()!
    }
}

// MARK: - GIF output

private struct GIF {
    private var frames: [(CGImage, Double)] = []

    mutating func add(_ image: CGImage, delay: Double) {
        frames.append((image, delay))
    }

    /// Writes numbered PNG frames plus a frames.txt timing file next to the GIF, so a better
    /// encoder (gifski) can be used when available; falls back to ImageIO's encoder.
    func write(to url: URL) throws {
        let framesDir = url.deletingPathExtension().appendingPathExtension("frames")
        try? FileManager.default.removeItem(at: framesDir)
        try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
        var timing = ""
        for (i, (image, delay)) in frames.enumerated() {
            let name = String(format: "%04d.png", i)
            try Self.writePNG(image, to: framesDir.appendingPathComponent(name))
            timing += "\(name) \(delay)\n"
        }
        try timing.write(to: framesDir.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (image, delay) in frames {
            CGImageDestinationAddImage(dest, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }
}
