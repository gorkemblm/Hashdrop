import AppKit
import SwiftUI

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var channelName: String
    var server: String
    var text: String
    var hasImage: Bool

    var link: URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range)?.url
    }
}

final class HistoryStore: ObservableObject {
    static let limit = 50

    @Published private(set) var entries: [HistoryEntry] = []
    /// nil = in-memory only (used by the demo renderer).
    private let fileURL: URL?

    init(inMemory entries: [HistoryEntry]) {
        fileURL = nil
        self.entries = entries
    }

    init() {
        let fileURL = AppPaths.supportDirectory.appendingPathComponent("history.json")
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
        save()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Menu bar panel

struct HistoryView: View {
    @ObservedObject var history: HistoryStore
    @ObservedObject var store: SettingsStore
    /// "Clear" wipes the recently copied links too, not just the send history.
    @ObservedObject var clipboard: ClipboardWatcher
    var onSendClipboard: () -> Void
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    static let width: CGFloat = 360
    private static let rowHeight: CGFloat = 62

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().opacity(0.5)

            list

            Divider().opacity(0.5)

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: Self.width)
        .background { GlassBackground(cornerRadius: 22) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "number")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Hashdrop")
                    .font(.system(size: 13, weight: .semibold))
                Text(history.entries.isEmpty ? "Nothing sent yet" : "Recently sent")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HeaderButton(symbol: "square.and.pencil", help: "Send clipboard (\(store.settings.hotKey.displayString))", action: onSendClipboard)
            HeaderButton(symbol: "gearshape", help: "Settings", action: onOpenSettings)
        }
    }

    @ViewBuilder
    private var list: some View {
        if history.entries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Copy a link and press \(store.settings.hotKey.displayString)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(history.entries.enumerated()), id: \.element.id) { index, entry in
                        HistoryRow(entry: entry, index: index, onRemove: { history.remove(entry.id) })
                            .frame(height: Self.rowHeight)
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.automatic)
            .frame(height: min(CGFloat(history.entries.count) * (Self.rowHeight + 4) + 16, 400))
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("\(store.settings.hotKey.displayString) to send")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            if !history.entries.isEmpty || !clipboard.links.isEmpty {
                FooterButton(title: "Clear") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        history.clear()
                        clipboard.clear()
                    }
                }
                .help("Clear recent sends and recently copied links")
            }
            FooterButton(title: "Quit", action: onQuit)
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let index: Int
    var onRemove: () -> Void

    @State private var hovering = false
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.hasImage ? "photo" : (entry.link != nil ? "link" : "text.alignleft"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("#\(entry.channelName)")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if !entry.server.isEmpty {
                        Text(entry.server)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(relative(entry.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Text(entry.text.isEmpty ? "Image" : entry.text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.primary.opacity(hovering ? 0.08 : 0))
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onTapGesture { open() }
        .contextMenu {
            if let link = entry.link {
                Button("Open Link") { NSWorkspace.shared.open(link) }
            }
            Button("Copy Message") { copy() }
            Divider()
            Button("Remove", role: .destructive, action: onRemove)
        }
        .help(entry.link != nil ? "Click to open link" : "Click to copy")
        // Rows cascade in one after another.
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -6)
        .onAppear {
            withAnimation(.spring(duration: 0.35).delay(Double(min(index, 10)) * 0.03)) { appeared = true }
        }
    }

    private func open() {
        if let link = entry.link {
            NSWorkspace.shared.open(link)
        } else {
            copy()
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }

    private func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(.primary.opacity(hovering ? 0.1 : 0.05), in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct FooterButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
