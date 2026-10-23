import SwiftUI

@MainActor
final class ComposerModel: ObservableObject {
    /// The comment. Typing "#name" at the start picks a channel; ⏎ or a space moves it into the
    /// channel pill, so the field only ever holds the comment. "##" escapes a literal leading "#".
    @Published var input = "" {
        didSet { inputChanged() }
    }
    @Published var selectedID: UUID?
    @Published var isSending = false
    @Published var errorMessage: String?
    /// 0 = what's on the clipboard now, n = recentLinks[n - 1].
    @Published var sourceIndex = 0
    /// Hold-⏎-to-send progress, 0...1.
    @Published var holdProgress: Double = 0
    /// Brief nudge after a ⏎ tap that was too short to send.
    @Published private(set) var showHoldHint = false

    static let holdDuration: TimeInterval = 0.5

    let clip: ClipContent
    /// Earlier copied links, newest first, excluding the current clipboard.
    let recentLinks: [String]
    let store: SettingsStore
    var onSend: (Channel, String) async throws -> Void = { _, _ in }
    var onClose: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    private var holdWork: DispatchWorkItem?
    private var hintWork: DispatchWorkItem?
    private var isCommittingChannel = false

    init(clip: ClipContent, recentLinks: [String], store: SettingsStore) {
        self.clip = clip
        self.recentLinks = recentLinks.filter { $0 != clip.text }
        self.store = store
        selectedID = filtered.first?.id
        if clip.isEmpty && !self.recentLinks.isEmpty {
            sourceIndex = 1
        }
    }

    /// What will actually be sent: the clipboard, or an older link the user picked.
    var activeClip: ClipContent {
        sourceIndex == 0 ? clip : ClipContent(text: recentLinks[sourceIndex - 1], image: nil)
    }

    func selectSource(_ index: Int) {
        guard index >= 0, index <= recentLinks.count else { return }
        withAnimation(.easeOut(duration: 0.15)) { sourceIndex = index }
    }

    // MARK: Channel picking

    /// Still typing the "#chan" part.
    var isTypingChannel: Bool {
        input.hasPrefix("#") && !input.hasPrefix("##") && !input.contains(where: \.isWhitespace)
    }

    var channelQuery: String { isTypingChannel ? String(input.dropFirst()) : "" }

    var comment: String { input.hasPrefix("##") ? String(input.dropFirst()) : input }

    private func inputChanged() {
        guard !isCommittingChannel else { return }
        // "#hab " — the space commits the channel into the pill (if it matches anything).
        if input.hasPrefix("#"), !input.hasPrefix("##"), let space = input.firstIndex(where: \.isWhitespace) {
            let token = String(input[input.index(after: input.startIndex)..<space])
            let matches = channels(matching: token)
            if let match = matches.first(where: { $0.id == selectedID }) ?? matches.first {
                selectedID = match.id
                setInputQuietly(String(input[space...].drop(while: \.isWhitespace)))
            }
            return
        }
        guard isTypingChannel else { return }
        let matches = filtered
        if !matches.contains(where: { $0.id == selectedID }) {
            selectedID = matches.first?.id
        }
    }

    /// "#hab" + ⏎ → channel goes into the pill, field is left for the comment.
    func completeChannel() {
        guard let channel = selected, filtered.contains(where: { $0.id == channel.id }) else {
            NSSound.beep()
            return
        }
        setInputQuietly("")
    }

    private func setInputQuietly(_ value: String) {
        isCommittingChannel = true
        input = value
        isCommittingChannel = false
    }

    /// Channel names as typed after "#": spaces become dashes, like Discord.
    static func token(for channel: Channel) -> String {
        channel.displayName.replacingOccurrences(of: " ", with: "-")
    }

    /// Most recently used first, filtered by the "#word" being typed.
    var filtered: [Channel] { channels(matching: channelQuery) }

    private func channels(matching query: String) -> [Channel] {
        let sorted = store.settings.channels.enumerated().sorted { a, b in
            switch (a.element.lastUsed, b.element.lastUsed) {
            case let (x?, y?): return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)

        let query = normalize(query)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { channel in
            normalize("\(channel.name) \(Self.token(for: channel)) \(channel.server)").contains(query)
        }
    }

    var selected: Channel? {
        store.settings.channels.first { $0.id == selectedID }
    }

    func move(_ delta: Int) {
        let list = filtered
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == selectedID } ?? -1
        selectedID = list[max(0, min(list.count - 1, index + delta))].id
    }

    // MARK: Sending

    /// ⏎ pressed. A tap completes "#chan"; otherwise holding it fills the Send button and sends.
    /// Clicks and ⌘⏎ call `send()` directly.
    func returnDown() {
        guard !isSending, holdWork == nil else { return }
        if isTypingChannel {
            completeChannel()
            return
        }
        guard store.settings.holdReturnToSend, selected != nil else {
            send()
            return
        }
        showHoldHint = false
        withAnimation(.linear(duration: Self.holdDuration)) { holdProgress = 1 }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.holdWork = nil
                self?.send()
            }
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDuration, execute: work)
    }

    /// ⏎ released before the hold finished: cancel and nudge.
    func returnUp() {
        guard let work = holdWork else { return }
        work.cancel()
        holdWork = nil
        withAnimation(.easeOut(duration: 0.15)) { holdProgress = 0 }

        hintWork?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { showHoldHint = true }
        let hide = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                withAnimation(.easeOut(duration: 0.3)) { self?.showHoldHint = false }
            }
        }
        hintWork = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: hide)
    }

    func send() {
        guard !isSending else { return }
        guard let channel = selected else {
            errorMessage = "Pick a channel first."
            return
        }
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await onSend(channel, comment)
            } catch {
                errorMessage = error.localizedDescription
                withAnimation(.easeOut(duration: 0.15)) { holdProgress = 0 }
                if store.settings.playSound { NSSound(named: "Basso")?.play() }
            }
            isSending = false
        }
    }

    private func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

struct ComposerView: View {
    @ObservedObject var model: ComposerModel
    @FocusState private var inputFocused: Bool
    @State private var appeared = false

    static let width: CGFloat = 480
    static let cornerRadius: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            preview
            if !model.recentLinks.isEmpty {
                sourcePicker
            }
            inputField
            channelList
            footer
        }
        .padding(16)
        .frame(width: Self.width)
        .background { GlassBackground(cornerRadius: Self.cornerRadius) }
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onExitCommand { model.onClose() }
        .onAppear {
            // Wait a tick so the panel is key before focusing.
            DispatchQueue.main.async { inputFocused = true }
            withAnimation(.spring(duration: 0.28, bounce: 0.25)) { appeared = true }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "number")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.gradient, in: Circle())
            Text("Hashdrop")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            HeaderButton(symbol: "gearshape", help: "Settings", action: model.onOpenSettings)
            HeaderButton(symbol: "xmark", help: "Close (esc)", action: model.onClose)
        }
    }

    @ViewBuilder
    private var preview: some View {
        Group {
            if let image = model.activeClip.image {
                Image(nsImage: image.preview)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: 110)
                    .clipped()
            } else if let text = model.activeClip.text {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: text.hasPrefix("http") ? "link" : "text.quote")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    // Always two lines tall, so switching between short and long links never shifts the panel.
                    Text(text)
                        .font(.system(size: 12))
                        .lineLimit(2, reservesSpace: true)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
            } else {
                Text("Clipboard is empty — only your comment will be sent.")
                    .font(.system(size: 12))
                    .lineLimit(2, reservesSpace: true)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
        // An image clipboard keeps the image-sized box even while a recent link is previewed.
        .frame(maxWidth: .infinity, minHeight: model.clip.image != nil ? 110 : nil, maxHeight: model.clip.image != nil ? 110 : nil, alignment: .topLeading)
        .background(.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var linkModifier: LinkPickerModifier { model.store.settings.linkPickerModifier }

    /// Chips for the clipboard plus recently copied links; modifier + ← / → steps through them.
    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Recent links")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                KeyCap(text: "\(linkModifier.symbol)←", enabled: model.sourceIndex > 0) {
                    model.selectSource(model.sourceIndex - 1)
                }
                .help("Newer")
                KeyCap(text: "\(linkModifier.symbol)→", enabled: model.sourceIndex < model.recentLinks.count) {
                    model.selectSource(model.sourceIndex + 1)
                }
                .help("Older")
            }
            chipStrip
        }
    }

    private var chipStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    sourceChip(
                        index: 0,
                        title: model.clip.image != nil ? "Image" : model.clip.text.flatMap(ClipboardWatcher.link(from:)).map(ClipboardWatcher.shortLabel(for:)) ?? "Clipboard",
                        symbol: "doc.on.clipboard",
                        help: "Current clipboard"
                    )
                    ForEach(Array(model.recentLinks.enumerated()), id: \.offset) { offset, link in
                        sourceChip(index: offset + 1, title: ClipboardWatcher.shortLabel(for: link), symbol: "link", help: link)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.never)
            .onChange(of: model.sourceIndex) { _, index in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
        .background {
            // Invisible buttons so the shortcut wins over the text fields' own cursor movement.
            Button("") { model.selectSource(model.sourceIndex - 1) }
                .keyboardShortcut(.leftArrow, modifiers: linkModifier.eventModifiers)
                .opacity(0)
                .allowsHitTesting(false)
            Button("") { model.selectSource(model.sourceIndex + 1) }
                .keyboardShortcut(.rightArrow, modifiers: linkModifier.eventModifiers)
                .opacity(0)
                .allowsHitTesting(false)
        }
    }

    private func sourceChip(index: Int, title: String, symbol: String, help: String) -> some View {
        let isSelected = model.sourceIndex == index
        return Button { model.selectSource(index) } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(isSelected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.primary.opacity(0.07)))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .id(index)
    }

    private var inputField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Where this is going, always visible.
            Text("#\(model.selected?.displayName ?? "?")")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(model.selected == nil ? Color.secondary.gradient : Color.accentColor.gradient, in: Capsule())
                .animation(.easeOut(duration: 0.12), value: model.selectedID)
            // ⏎ is handled by the panel's key monitor (tap vs. hold), not onSubmit.
            TextField("Add a comment…  (#name switches channel)", text: $model.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .focused($inputFocused)
        }
        .modifier(FieldChrome(isFocused: inputFocused))
    }

    @ViewBuilder
    private var channelList: some View {
        let channels = model.filtered
        // Height follows the total channel count, not the filtered one, so the panel never jumps while typing.
        let height = min(CGFloat(max(model.store.settings.channels.count, 2)), 5) * 36

        Group {
            if model.store.settings.channels.isEmpty {
                VStack(spacing: 6) {
                    Text("No channels yet").foregroundStyle(.secondary)
                    Button("Add one in Settings") { model.onOpenSettings() }
                        .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if channels.isEmpty {
                Text("No channel matches #\(model.channelQuery)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(channels) { channel in
                                row(channel)
                                    .id(channel.id)
                                    .onTapGesture(count: 2) {
                                        model.selectedID = channel.id
                                        model.send()
                                    }
                                    .onTapGesture { model.selectedID = channel.id }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .onChange(of: model.selectedID) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
                    }
                }
            }
        }
        .font(.system(size: 12))
        .frame(height: height)
    }

    private func row(_ channel: Channel) -> some View {
        let isSelected = channel.id == model.selectedID
        return HStack(spacing: 10) {
            Text("#")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(channel.displayName)
                    .font(.system(size: 13, weight: .medium))
                if !channel.server.isEmpty {
                    Text(channel.server)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? .white.opacity(0.75) : .secondary)
                }
            }
            Spacer()
            if !channel.isConfigured {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("Missing webhook URL or channel link")
            }
            Image(systemName: channel.method == .webhook ? "bolt.fill" : "person.fill")
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                .help(channel.method == .webhook ? "Sends via Discord webhook" : "Sends from your account via the Discord app")
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.gradient)
            }
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var hint: String {
        if model.isTypingChannel {
            return "↑↓ choose · ⏎ pick channel · esc close"
        }
        var parts = ["↑↓ channel"]
        if !model.recentLinks.isEmpty { parts.append("\(linkModifier.symbol)←→ link") }
        parts.append(model.store.settings.holdReturnToSend ? "hold ⏎ to send" : "⏎ send")
        return parts.joined(separator: " · ")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .help(error)
            } else if model.showHoldHint {
                Text("Hold ⏎ to send")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            } else if model.holdProgress > 0, let channel = model.selected {
                (Text("Sending to ") + Text("#\(channel.displayName)").bold() + Text("…"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .transition(.opacity)
            } else {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
            Spacer()
            Button { model.send() } label: {
                HStack(spacing: 6) {
                    if model.isSending {
                        ProgressView().controlSize(.mini).tint(.white)
                    }
                    Text("Send")
                    Image(systemName: "arrow.up")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.accentColor.gradient, in: Capsule())
                .overlay(alignment: .leading) {
                    // Fills left to right while ⏎ is held.
                    GeometryReader { geo in
                        Capsule()
                            .fill(.white.opacity(0.35))
                            .frame(width: geo.size.width * model.holdProgress)
                    }
                }
                .clipShape(Capsule())
                .scaleEffect(model.holdProgress > 0 ? 0.95 : 1)
                .animation(.spring(duration: 0.2), value: model.holdProgress > 0)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.isSending || model.selected == nil)
            .opacity(model.selected == nil ? 0.5 : 1)
        }
    }
}

extension LinkPickerModifier {
    var eventModifiers: EventModifiers {
        switch self {
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shiftCommand: return [.shift, .command]
        }
    }
}

/// Small clickable keyboard-key badge, e.g. "⌘←".
private struct KeyCap: View {
    let text: String
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(enabled ? .primary : .tertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.primary.opacity(hovering && enabled ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.primary.opacity(0.15), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

private struct FieldChrome: ViewModifier {
    var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.primary.opacity(isFocused ? 0.09 : 0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isFocused ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// Liquid Glass on macOS 26+, frosted behind-window blur before that.
struct GlassBackground: View {
    var cornerRadius: CGFloat
    @Environment(\.stillRender) private var stillRender

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if stillRender {
            // Offscreen renders can't sample what's behind the window; the demo renderer blurs the backdrop itself.
            shape.fill(Color(white: 0.1).opacity(0.55))
                .overlay { shape.strokeBorder(.white.opacity(0.16), lineWidth: 0.5) }
        } else if #available(macOS 26, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            VisualEffectBlur()
                .clipShape(shape)
                .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
        }
    }
}

private struct StillRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when views are being drawn offscreen for README images.
    var stillRender: Bool {
        get { self[StillRenderKey.self] }
        set { self[StillRenderKey.self] = newValue }
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
