import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        TabView {
            ChannelsTab(store: store)
                .tabItem { Label("Channels", systemImage: "number") }
            GeneralTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding()
        .frame(width: 680, height: 460)
    }
}

// MARK: - Channels

private struct ChannelsTab: View {
    @ObservedObject var store: SettingsStore
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.settings.channels) { channel in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("# \(channel.displayName)")
                            Text([channel.server, channel.method.label].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(channel.id)
                    }
                    .onMove { store.settings.channels.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack(spacing: 0) {
                    Button { add() } label: { Image(systemName: "plus").frame(width: 24, height: 22) }
                    Button { remove() } label: { Image(systemName: "minus").frame(width: 24, height: 22) }
                        .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 210)
            .border(.separator)

            Group {
                if let id = selection, store.settings.channels.contains(where: { $0.id == id }) {
                    ChannelEditor(channel: binding(for: id))
                        .id(id)
                } else {
                    Text("Add a channel with + to get started.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { selection = selection ?? store.settings.channels.first?.id }
    }

    private func add() {
        let channel = Channel()
        store.settings.channels.append(channel)
        selection = channel.id
    }

    private func remove() {
        guard let id = selection else { return }
        store.settings.channels.removeAll { $0.id == id }
        selection = store.settings.channels.first?.id
    }

    /// Looks the channel up by id so deleting it never leaves a dangling index.
    private func binding(for id: UUID) -> Binding<Channel> {
        Binding(
            get: { store.settings.channels.first { $0.id == id } ?? Channel() },
            set: { updated in
                if let i = store.settings.channels.firstIndex(where: { $0.id == id }) {
                    store.settings.channels[i] = updated
                }
            }
        )
    }
}

private struct ChannelEditor: View {
    @Binding var channel: Channel
    @State private var testStatus: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                TextField("Channel name", text: $channel.name, prompt: Text("e.g. news"))
                TextField("Server", text: $channel.server, prompt: Text("optional, helps searching"))
            }

            Section {
                Picker("Send via", selection: $channel.method) {
                    ForEach(DeliveryMethod.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                switch channel.method {
                case .webhook:
                    TextField("Webhook URL", text: $channel.webhookURL, prompt: Text("https://discord.com/api/webhooks/…"))
                    status(ok: channel.webhookIsValid, okText: "Looks good", badText: "Paste a Discord webhook URL")
                    Text("Server Settings → Integrations → Webhooks → New Webhook → Copy Webhook URL. Needs the Manage Webhooks permission. Sends silently in the background, posted under the webhook's name and avatar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Send test message") { test() }
                            .disabled(!channel.webhookIsValid || testing)
                        if let testStatus {
                            Text(testStatus).font(.caption)
                        }
                    }
                case .app:
                    TextField("Channel link", text: $channel.channelLink, prompt: Text("https://discord.com/channels/…/…"))
                    status(ok: channel.deepLink != nil, okText: "Looks good", badText: "Paste a channel link")
                    Text("In Discord, right-click the channel → Copy Link. Works in any server, as your own account: Hashdrop briefly brings Discord forward, pastes and presses Return. Needs Accessibility permission (see General).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func status(ok: Bool, okText: String, badText: String) -> some View {
        Label(ok ? okText : badText, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(ok ? .green : .secondary)
    }

    private func test() {
        testing = true
        testStatus = nil
        Task {
            do {
                try await WebhookSender.send(to: channel.webhookURL, text: "✅ Hashdrop is connected.", image: nil)
                testStatus = "Sent ✓"
            } catch {
                testStatus = error.localizedDescription
            }
            testing = false
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var store: SettingsStore
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent("Shortcut") {
                    HotKeyRecorder(combo: $store.settings.hotKey)
                }
                Picker("Message order", selection: $store.settings.order) {
                    ForEach(MessageOrder.allCases) { Text($0.label).tag($0) }
                }
                Toggle(isOn: $store.settings.holdReturnToSend) {
                    Text("Hold ⏎ to send")
                    Text("A quick ⏎ never sends, so a stray keypress can't post by accident. Clicking Send or ⌘⏎ sends right away.")
                }
                Toggle("Return to the previous app after sending", isOn: $store.settings.returnToPreviousApp)
                Toggle("Play a sound when a message is sent", isOn: $store.settings.playSound)
                Toggle(isOn: $store.settings.clipboardHistory) {
                    Text("Remember the last 10 copied links")
                    Text("Kept in memory only, cleared on quit; copies from password managers are ignored.")
                }
                Picker(selection: $store.settings.linkPickerModifier) {
                    ForEach(LinkPickerModifier.allCases) { Text($0.label).tag($0) }
                } label: {
                    Text("Switch links with")
                    Text(linkPickerFootnote)
                }
                .disabled(!store.settings.clipboardHistory)
            }

            Section {
                LabeledContent("Accessibility") {
                    if accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant…") { openAccessibilitySettings() }
                    }
                }
                LabeledContent("Wait for channel to load") {
                    HStack {
                        Slider(value: $store.settings.appModeDelay, in: 0.3...3, step: 0.1)
                            .frame(width: 180)
                        Text(String(format: "%.1f s", store.settings.appModeDelay))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text("Discord app sending")
            } footer: {
                Text("Increase the wait if messages land in the wrong channel or don't send.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in accessibilityGranted = AXIsProcessTrusted() }
    }

    private var linkPickerFootnote: String {
        let m = store.settings.linkPickerModifier
        var note = "\(m.symbol)← / \(m.symbol)→ in the send panel."
        switch m {
        case .command: note += " Replaces jump-to-line-start/end inside its text fields."
        case .option: note += " Replaces word-by-word cursor moves inside its text fields."
        case .control: note += " macOS may use ⌃← / ⌃→ to switch Spaces; turn that off in Keyboard Shortcuts → Mission Control if it clashes."
        case .shiftCommand: note += " Replaces select-to-line-start/end inside its text fields."
        }
        return note
    }

    private func openAccessibilitySettings() {
        DiscordAppSender.requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct HotKeyRecorder: View {
    @Binding var combo: HotKeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press a shortcut… (esc cancels)" : combo.displayString) {
            recording ? stop() : start()
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.intersection([.command, .option, .control]).isEmpty else {
                NSSound.beep() // require ⌘, ⌥ or ⌃ so plain typing never triggers it
                return nil
            }
            combo = HotKeyCombo(
                keyCode: UInt32(event.keyCode),
                carbonModifiers: HotKeyManager.carbonModifiers(from: flags),
                keyLabel: HotKeyManager.keyLabel(for: event)
            )
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            HotKeyManager.shared.resume()
        }
    }
}
