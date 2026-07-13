import AppKit
import ClipFlowCore
import Foundation

public final class SystemClipboard: PasteboardAccess, @unchecked Sendable {
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
}
