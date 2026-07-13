import AppKit
import ClipFlowCore
import Foundation

public final class SystemClipboard: PasteboardAccess, ClipboardWriting,
    ApplicationActionClipboard, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int {
        pasteboard.changeCount
    }

    public func snapshot() -> RawClipboardCapture? {
        guard let pasteboardItems = pasteboard.pasteboardItems else { return nil }

        let items = pasteboardItems.compactMap { item -> RawClipboardItem? in
            let representations = item.types.compactMap { type -> RawClipboardRepresentation? in
                guard let data = item.data(forType: type) else { return nil }
                return RawClipboardRepresentation(type: type.rawValue, data: data)
            }
            return representations.isEmpty ? nil : RawClipboardItem(representations: representations)
        }
        guard !items.isEmpty else { return nil }

        let sourceApplication = NSWorkspace.shared.frontmostApplication
        return RawClipboardCapture(
            sourceAppName: sourceApplication?.localizedName ?? "Unknown",
            sourceBundleID: sourceApplication?.bundleIdentifier,
            items: items
        )
    }

    public func captureActionSnapshot() throws -> ClipboardSnapshot {
        let payloads = (pasteboard.pasteboardItems ?? []).enumerated().flatMap { itemIndex, item in
            item.types.compactMap { type -> NormalizedPayload? in
                guard let data = item.data(forType: type) else { return nil }
                return NormalizedPayload(itemIndex: itemIndex, type: type.rawValue, data: data)
            }
        }
        return ClipboardSnapshot(payloads: payloads)
    }

    public func write(_ payloads: [NormalizedPayload]) throws {
        _ = try write(payloads: payloads, mode: .original)
    }

    public func restore(_ snapshot: ClipboardSnapshot) throws {
        if snapshot.payloads.isEmpty {
            pasteboard.clearContents()
        } else {
            _ = try write(payloads: snapshot.payloads, mode: .original)
        }
    }

    @discardableResult
    public func write(payloads: [NormalizedPayload], mode: PasteMode) throws -> Int {
        let objects: [NSPasteboardItem]
        switch mode {
        case .original:
            objects = Dictionary(grouping: payloads, by: \.itemIndex)
                .sorted { $0.key < $1.key }
                .map { _, payloads in
                    let item = NSPasteboardItem()
                    for payload in payloads {
                        item.setData(payload.data, forType: NSPasteboard.PasteboardType(payload.type))
                    }
                    return item
                }
        case .plainText:
            guard let text = Self.plainText(from: payloads) else {
                throw PasteSystemError.noPlainTextRepresentation
            }
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            objects = [item]
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects(objects) else {
            throw PasteSystemError.pasteboardWriteFailed
        }
        return pasteboard.changeCount
    }

    private static func plainText(from payloads: [NormalizedPayload]) -> String? {
        let preferredTypes = [
            "public.utf8-plain-text",
            "public.plain-text",
            "public.url",
            "public.file-url"
        ]
        for type in preferredTypes {
            if let payload = payloads.first(where: { $0.type == type }),
               let text = String(data: payload.data, encoding: .utf8) {
                return text
            }
        }

        if let rtf = payloads.first(where: { $0.type == "public.rtf" }),
           let attributed = NSAttributedString(rtf: rtf.data, documentAttributes: nil) {
            return attributed.string
        }
        if let html = payloads.first(where: { $0.type == "public.html" }),
           let attributed = NSAttributedString(
               html: html.data,
               options: [.documentType: NSAttributedString.DocumentType.html],
               documentAttributes: nil
           ) {
            return attributed.string
        }
        return nil
    }
}
