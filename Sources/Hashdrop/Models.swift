import Carbon.HIToolbox
import Combine
import Foundation

enum DeliveryMethod: String, Codable, CaseIterable, Identifiable {
    case webhook
    case app

    var id: String { rawValue }

    var label: String {
        switch self {
        case .webhook: return "Discord webhook"
        case .app: return "Discord app"
        }
    }
}

struct Channel: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var server = ""
    var method: DeliveryMethod = .app
    var webhookURL = ""
    var channelLink = ""
    var lastUsed: Date?

    var displayName: String { name.isEmpty ? "Untitled channel" : name }

    /// Accepts links copied via "Copy Link" in Discord (discord.com, ptb, canary, discordapp.com).
    static func parseIDs(_ link: String) -> (guild: String, channel: String)? {
        let parts = link.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/").map(String.init)
        guard let i = parts.firstIndex(of: "channels"), parts.count > i + 2 else { return nil }
        let guild = parts[i + 1], channel = parts[i + 2]
        guard guild == "@me" || guild.allSatisfy(\.isNumber), channel.allSatisfy(\.isNumber) else { return nil }
        return (guild, channel)
    }

    var deepLink: URL? {
        guard let ids = Channel.parseIDs(channelLink) else { return nil }
        return URL(string: "discord://-/channels/\(ids.guild)/\(ids.channel)")
    }

    var webhookIsValid: Bool {
        guard let url = URL(string: webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme == "https" && url.path.contains("/api/webhooks/")
    }

    var isConfigured: Bool {
        switch method {
        case .webhook: return webhookIsValid
        case .app: return deepLink != nil
        }
    }
}

struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyLabel: String

    static let `default` = HotKeyCombo(
        keyCode: UInt32(kVK_ANSI_D),
        carbonModifiers: UInt32(optionKey | shiftKey),
        keyLabel: "D"
    )

    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyLabel
    }
}

/// Modifier held with ← / → to step through recent links in the send panel.
enum LinkPickerModifier: String, Codable, CaseIterable, Identifiable {
    case command
    case option
    case control
    case shiftCommand

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shiftCommand: return "⇧⌘"
        }
    }

    var label: String {
        switch self {
        case .command: return "⌘ Command"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .shiftCommand: return "⇧⌘ Shift-Command"
        }
    }
}

enum MessageOrder: String, Codable, CaseIterable, Identifiable {
    case commentFirst
    case contentFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .commentFirst: return "Comment, then clipboard"
        case .contentFirst: return "Clipboard, then comment"
        }
    }
}

struct AppSettings: Codable {
    var channels: [Channel] = []
    var hotKey: HotKeyCombo = .default
    var order: MessageOrder = .commentFirst
    var returnToPreviousApp = true
    /// Extra wait after Discord comes to the front, so the channel has time to load.
    var appModeDelay: Double = 0.8
    var playSound = true
    var clipboardHistory = true
    var linkPickerModifier: LinkPickerModifier = .command
    var holdReturnToSend = true

    init() {}

    /// Missing keys fall back to defaults, so adding a setting never resets an existing config.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        channels = try c.decodeIfPresent([Channel].self, forKey: .channels) ?? d.channels
        hotKey = try c.decodeIfPresent(HotKeyCombo.self, forKey: .hotKey) ?? d.hotKey
        order = try c.decodeIfPresent(MessageOrder.self, forKey: .order) ?? d.order
        returnToPreviousApp = try c.decodeIfPresent(Bool.self, forKey: .returnToPreviousApp) ?? d.returnToPreviousApp
        appModeDelay = try c.decodeIfPresent(Double.self, forKey: .appModeDelay) ?? d.appModeDelay
        playSound = try c.decodeIfPresent(Bool.self, forKey: .playSound) ?? d.playSound
        clipboardHistory = try c.decodeIfPresent(Bool.self, forKey: .clipboardHistory) ?? d.clipboardHistory
        linkPickerModifier = try c.decodeIfPresent(LinkPickerModifier.self, forKey: .linkPickerModifier) ?? d.linkPickerModifier
        holdReturnToSend = try c.decodeIfPresent(Bool.self, forKey: .holdReturnToSend) ?? d.holdReturnToSend
    }
}

enum AppPaths {
    /// ~/Library/Application Support/Hashdrop — moved over from the pre-rename "RouteToDC" folder once.
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Hashdrop", isDirectory: true)
        let legacy = base.appendingPathComponent("RouteToDC", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path), fm.fileExists(atPath: legacy.path) {
            try? fm.moveItem(at: legacy, to: dir)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    /// nil = in-memory only (used by the demo renderer, never touches the user's config).
    private let fileURL: URL?

    init(inMemory settings: AppSettings) {
        fileURL = nil
        self.settings = settings
    }

    init() {
        let fileURL = AppPaths.supportDirectory.appendingPathComponent("settings.json")
        self.fileURL = fileURL

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        // Webhook URLs are credentials; keep the file private to the user.
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func markUsed(_ id: UUID) {
        guard let i = settings.channels.firstIndex(where: { $0.id == id }) else { return }
        settings.channels[i].lastUsed = Date()
    }
}
