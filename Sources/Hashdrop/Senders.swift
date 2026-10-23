import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum SendError: LocalizedError {
    case notConfigured
    case nothingToSend
    case tooLong(Int)
    case webhook(status: Int, message: String)
    case discordNotInstalled
    case discordDidNotOpen
    case needsAccessibility

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "This channel isn't set up yet. Open Settings to add its webhook URL or channel link."
        case .nothingToSend:
            return "Clipboard is empty and there's no comment."
        case .tooLong(let n):
            return "Message is \(n) characters; Discord's limit is 2000."
        case .webhook(let status, let message):
            return "Discord rejected the webhook (\(status)): \(message)"
        case .discordNotInstalled:
            return "Discord app not found. Install Discord or use a webhook for this channel."
        case .discordDidNotOpen:
            return "Discord didn't come to the front in time."
        case .needsAccessibility:
            return "Hashdrop needs Accessibility permission to paste into Discord. Enable it in System Settings → Privacy & Security → Accessibility, then try again."
        }
    }
}

enum WebhookSender {
    static func send(to urlString: String, text: String, image: ImageAttachment?) async throws {
        guard var components = URLComponents(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SendError.notConfigured
        }
        components.queryItems = [URLQueryItem(name: "wait", value: "true")]
        guard let url = components.url else { throw SendError.notConfigured }

        // Never ping @everyone / roles by accident from a clipboard paste.
        let payload: [String: Any] = ["content": text, "allowed_mentions": ["parse": []]]
        let json = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let image {
            let boundary = "Hashdrop-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n")
            body.append(json)
            body.append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"files[0]\"; filename=\"\(image.filename)\"\r\nContent-Type: \(image.mimeType)\r\n\r\n")
            body.append(image.data)
            body.append("\r\n--\(boundary)--\r\n")
            request.httpBody = body
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = json
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw SendError.webhook(status: status, message: message ?? String(decoding: data, as: UTF8.self))
        }
    }
}

/// Sends as the user's own account by driving the Discord desktop app:
/// open the channel via deep link, paste, press Return.
@MainActor
enum DiscordAppSender {
    static func send(to deepLink: URL, text: String, image: ImageAttachment?, delay: Double) async throws {
        guard AXIsProcessTrusted() else {
            requestAccessibility()
            throw SendError.needsAccessibility
        }
        guard NSWorkspace.shared.urlForApplication(toOpen: deepLink) != nil else {
            throw SendError.discordNotInstalled
        }

        let wasRunning = NSWorkspace.shared.runningApplications.contains { isDiscord($0.bundleIdentifier) }
        NSWorkspace.shared.open(deepLink)

        // Cold start includes Discord's update check, so give it much longer.
        let deadline = Date().addingTimeInterval(wasRunning ? 5 : 30)
        while !isDiscord(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
            guard Date() < deadline else { throw SendError.discordDidNotOpen }
            try await sleep(0.05)
        }
        try await sleep(wasRunning ? delay : delay + 5)

        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        defer { restore(saved, to: pasteboard) }

        if let image {
            pasteboard.clearContents()
            pasteboard.setData(image.data, forType: image.mimeType == "image/png" ? .png : NSPasteboard.PasteboardType("public.jpeg"))
            if let tiff = image.preview.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
            pressKey(kVK_ANSI_V, flags: .maskCommand)
            try await sleep(0.5)
        }
        if !text.isEmpty {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            pressKey(kVK_ANSI_V, flags: .maskCommand)
            try await sleep(0.2)
        }
        pressKey(kVK_Return)
        try await sleep(0.3)
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func isDiscord(_ bundleID: String?) -> Bool {
        bundleID?.hasPrefix("com.hnc.Discord") ?? false
    }

    private static func pressKey(_ code: Int, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func sleep(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
