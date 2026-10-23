import AppKit
import SwiftUI

/// Borderless, transparent, non-activating panel hosting a SwiftUI view.
/// Non-activating means it can take keyboard focus without pulling the user's current app to the background.
final class GlassPanel: NSPanel {
    private let interactive: Bool

    override var canBecomeKey: Bool { interactive }
    override var canBecomeMain: Bool { interactive }

    init<Content: View>(interactive: Bool, @ViewBuilder content: () -> Content) {
        self.interactive = interactive
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        ignoresMouseEvents = !interactive
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: content())
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        contentView = hosting
        setContentSize(hosting.fittingSize)
    }

    /// Fades in while sliding `offset` points into `frame`.
    func present(at frame: NSRect, slide offset: CGFloat) {
        setFrame(frame.offsetBy(dx: 0, dy: offset), display: false)
        alphaValue = 0
        if interactive {
            makeKeyAndOrderFront(nil)
        } else {
            orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(frame, display: true)
            animator().alphaValue = 1
        }
        // SwiftUI entrance animations change the content's alpha; recompute the shadow once they settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.invalidateShadow()
        }
    }

    func dismiss(duration: TimeInterval = 0.15) {
        delegate = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { self.orderOut(nil) }
        }
    }

    /// Resizes to the SwiftUI content's current size, keeping the top edge where it is.
    func fitContent() {
        guard let size = contentView?.fittingSize, size != frame.size else { return }
        setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true, animate: true)
        invalidateShadow()
    }

    // MARK: - Placement

    static func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    /// Centered horizontally, a little above the middle — where Spotlight sits.
    static func centeredFrame(size: NSSize) -> NSRect {
        guard let visible = screenWithMouse()?.visibleFrame else { return NSRect(origin: .zero, size: size) }
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.minY + visible.height * 0.6 - size.height / 2,
            width: size.width,
            height: size.height
        ).integral
    }

    /// Hangs just below the menu bar icon, kept on screen.
    static func frameBelow(_ anchor: NSWindow?, size: NSSize) -> NSRect {
        guard let visible = (anchor?.screen ?? NSScreen.main)?.visibleFrame else { return NSRect(origin: .zero, size: size) }
        var x = visible.maxX - size.width - 10
        if let anchor {
            x = min(max(anchor.frame.midX - size.width / 2, visible.minX + 10), visible.maxX - size.width - 10)
        }
        return NSRect(x: x, y: visible.maxY - size.height - 8, width: size.width, height: size.height).integral
    }
}
