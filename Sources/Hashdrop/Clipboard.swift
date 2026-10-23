import AppKit
import UniformTypeIdentifiers

struct ImageAttachment {
    var data: Data
    var filename: String
    var mimeType: String
    var preview: NSImage
}

/// Snapshot of what the user copied, taken when the hotkey is pressed.
struct ClipContent {
    var text: String?
    var image: ImageAttachment?

    var isEmpty: Bool { (text ?? "").isEmpty && image == nil }

    static func current() -> ClipContent {
        let pb = NSPasteboard.general

        // A copied image file in Finder.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first,
           let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
           let image = NSImage(contentsOf: url) {
            return ClipContent(text: nil, image: makeAttachment(image))
        }

        // "Copy Image" from a browser, screenshots to clipboard, etc.
        if pb.availableType(from: [.png, .tiff]) != nil, let image = NSImage(pasteboard: pb) {
            return ClipContent(text: nil, image: makeAttachment(image))
        }

        let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ClipContent(text: (text?.isEmpty ?? true) ? nil : text, image: nil)
    }

    private static func makeAttachment(_ image: NSImage) -> ImageAttachment? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        // Discord's default upload limit is 10 MB; fall back to JPEG for big screenshots.
        if let png = rep.representation(using: .png, properties: [:]), png.count < 9_000_000 {
            return ImageAttachment(data: png, filename: "image.png", mimeType: "image/png", preview: image)
        }
        if let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            return ImageAttachment(data: jpg, filename: "image.jpg", mimeType: "image/jpeg", preview: image)
        }
        return nil
    }
}

enum MessageBuilder {
    static func build(comment: String, content: String?, settings: AppSettings) -> String {
        var parts = [comment, content ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if settings.order == .contentFirst {
            parts.reverse()
        }
        return parts.joined(separator: "\n")
    }
}
