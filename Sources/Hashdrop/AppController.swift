import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = SettingsStore()
    let history = HistoryStore()
    let clipboard = ClipboardWatcher()
    private var statusItem: NSStatusItem!
    private var composer: GlassPanel?
    private var composerKeyMonitor: Any?
    private var historyPanel: GlassPanel?
    private var historyClosedAt = Date.distantPast
    private var settingsWindow: NSWindow?
    private var previousApp: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()
    private let toast = ToastController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        setUpStatusItem()

        HotKeyManager.shared.onPress = { [weak self] in self?.toggleComposer() }
        store.$settings
            .map(\.hotKey)
            .removeDuplicates()
            .sink { [weak self] combo in
                if !HotKeyManager.shared.register(combo) {
                    self?.showError("Couldn't register \(combo.displayString) — another app may be using it. Pick a different shortcut in Settings.")
                }
            }
            .store(in: &cancellables)

        store.$settings
            .map(\.clipboardHistory)
            .removeDuplicates()
            .sink { [weak self] enabled in self?.clipboard.setEnabled(enabled) }
            .store(in: &cancellables)

        // Keep the history panel snug when entries are added, removed or cleared while it's open.
        history.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.historyPanel?.fitContent() }
            }
            .store(in: &cancellables)

        if store.settings.channels.isEmpty {
            openSettings()
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(Self.icon)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private static let icon = "number"

    private func setIcon(_ symbol: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Hashdrop")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func flashIcon(_ symbol: String) {
        setIcon(symbol)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.setIcon(Self.icon)
        }
    }

    /// Accessory apps have no menu bar, so ⌘C/⌘V/⌘A would not work in text fields without this.
    private func installMainMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    // MARK: - History panel

    @objc private func statusItemClicked() {
        if historyPanel != nil {
            closeHistory()
        } else if Date().timeIntervalSince(historyClosedAt) > 0.3 {
            // The click that dismissed the panel (via resign-key) shouldn't immediately reopen it.
            showHistory()
        }
    }

    private func showHistory() {
        closeComposer(returnFocus: false)
        let panel = GlassPanel(interactive: true) {
            HistoryView(
                history: history,
                store: store,
                clipboard: clipboard,
                onSendClipboard: { [weak self] in
                    self?.closeHistory()
                    self?.toggleComposer()
                },
                onOpenSettings: { [weak self] in
                    self?.closeHistory()
                    self?.openSettings()
                },
                onQuit: { NSApp.terminate(nil) }
            )
        }
        panel.delegate = self
        historyPanel = panel
        statusItem.button?.highlight(true)
        panel.present(at: GlassPanel.frameBelow(statusItem.button?.window, size: panel.frame.size), slide: 14)
    }

    private func closeHistory() {
        guard let panel = historyPanel else { return }
        historyPanel = nil
        historyClosedAt = Date()
        statusItem.button?.highlight(false)
        panel.dismiss()
    }

    // MARK: - Composer

    private func toggleComposer() {
        if composer != nil {
            closeComposer(returnFocus: true)
            return
        }
        closeHistory()

        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front

        let model = ComposerModel(clip: .current(), recentLinks: clipboard.links, store: store)
        model.onClose = { [weak self] in self?.closeComposer(returnFocus: true) }
        model.onOpenSettings = { [weak self] in
            self?.closeComposer(returnFocus: false)
            self?.openSettings()
        }
        model.onSend = { [weak self, weak model] channel, comment in
            guard let self, let model else { return }
            try await self.send(clip: model.activeClip, comment: comment, to: channel)
        }

        let panel = GlassPanel(interactive: true) { ComposerView(model: model) }
        panel.delegate = self
        composer = panel

        // ⏎ (tap vs. hold) and ↑↓ (channel selection) are handled here, ahead of the text field.
        composerKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak panel, weak model] event in
            guard let panel, let model, event.window === panel,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            else { return event }

            if [kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode)) {
                // Let input methods (e.g. Japanese) use ⏎ to confirm composition.
                if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
                if event.type == .keyDown {
                    if !event.isARepeat { model.returnDown() }
                } else {
                    model.returnUp()
                }
                return nil
            }

            guard event.type == .keyDown else { return event }
            switch Int(event.keyCode) {
            case kVK_UpArrow:
                model.move(-1)
                return nil
            case kVK_DownArrow:
                model.move(1)
                return nil
            default:
                return event
            }
        }
        panel.present(at: GlassPanel.centeredFrame(size: panel.frame.size), slide: -8)
    }

    private func closeComposer(returnFocus: Bool) {
        guard let panel = composer else { return }
        composer = nil
        if let composerKeyMonitor { NSEvent.removeMonitor(composerKeyMonitor) }
        composerKeyMonitor = nil
        panel.dismiss()
        if returnFocus {
            previousApp?.activate()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking anywhere else dismisses the panels, like Spotlight and menu bar popovers.
        guard let window = notification.object as? NSWindow else { return }
        if window === composer {
            closeComposer(returnFocus: false)
        } else if window === historyPanel {
            closeHistory()
        }
    }

    // MARK: - Sending

    private func send(clip: ClipContent, comment: String, to channel: Channel) async throws {
        let text = MessageBuilder.build(comment: comment, content: clip.text, settings: store.settings)
        guard !text.isEmpty || clip.image != nil else { throw SendError.nothingToSend }
        guard text.count <= 2000 else { throw SendError.tooLong(text.count) }

        switch channel.method {
        case .webhook:
            guard channel.webhookIsValid else { throw SendError.notConfigured }
            try await WebhookSender.send(to: channel.webhookURL, text: text, image: clip.image)
            closeComposer(returnFocus: store.settings.returnToPreviousApp)

        case .app:
            guard let link = channel.deepLink else { throw SendError.notConfigured }
            guard AXIsProcessTrusted() else {
                DiscordAppSender.requestAccessibility()
                throw SendError.needsAccessibility
            }
            let returnTo = previousApp
            closeComposer(returnFocus: false)
            do {
                try await DiscordAppSender.send(to: link, text: text, image: clip.image, delay: store.settings.appModeDelay)
            } catch {
                flashIcon("exclamationmark.triangle.fill")
                toast.show("Couldn't send to #\(channel.displayName)", detail: error.localizedDescription,
                           style: .failure, sound: store.settings.playSound, below: statusItem.button?.window)
                return
            }
            if store.settings.returnToPreviousApp {
                returnTo?.activate()
            }
        }

        store.markUsed(channel.id)
        history.add(HistoryEntry(channelName: channel.displayName, server: channel.server, text: text, hasImage: clip.image != nil))
        flashIcon("checkmark.circle.fill")
        toast.show("Sent to #\(channel.displayName)", style: .success,
                   sound: store.settings.playSound, below: statusItem.button?.window)
    }

    private func showError(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Hashdrop"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Settings

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
            window.title = "Hashdrop Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
