import AppKit
import SwiftUI

/// Small glass toast that drops in below the menu bar icon and fades away on its own.
@MainActor
final class ToastController {
    enum Style {
        case success, failure

        var symbol: String { self == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }
        var color: Color { self == .success ? .green : .red }
        var sound: NSSound.Name { self == .success ? "Pop" : "Basso" }
        var duration: TimeInterval { self == .success ? 1.8 : 5 }
    }

    private var panel: GlassPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ title: String, detail: String? = nil, style: Style, sound: Bool, below anchor: NSWindow?) {
        if sound { NSSound(named: style.sound)?.play() }
        hideWork?.cancel()
        panel?.orderOut(nil)

        let panel = GlassPanel(interactive: false) {
            ToastView(title: title, detail: detail, style: style)
        }
        panel.present(at: GlassPanel.frameBelow(anchor, size: panel.frame.size), slide: 10)
        self.panel = panel

        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let panel else { return }
            panel.dismiss(duration: 0.3)
            if self?.panel === panel { self?.panel = nil }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + style.duration, execute: work)
    }
}

struct ToastView: View {
    let title: String
    let detail: String?
    let style: ToastController.Style
    @State private var appeared = false

    var body: some View {
        HStack(alignment: detail == nil ? .center : .top, spacing: 10) {
            Image(systemName: style.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(style.color.gradient)
                .symbolEffect(.bounce, value: appeared)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Short confirmations hug their text; error details wrap at a fixed width.
        .frame(width: detail == nil ? nil : 320, alignment: .leading)
        .background { GlassBackground(cornerRadius: 18) }
        .onAppear { appeared = true }
    }
}
