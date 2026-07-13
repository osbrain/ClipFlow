import AppKit
import ClipFlowCore
import Foundation

public struct ClipboardVisualDescriptor {
    public let itemID: UUID
    public let applicationIcon: NSImage?
    public let thumbnail: NSImage?
    public let kind: ClipboardKindPresentation

    public init(
        itemID: UUID,
        applicationIcon: NSImage?,
        thumbnail: NSImage?,
        kind: ClipboardKindPresentation
    ) {
        self.itemID = itemID
        self.applicationIcon = applicationIcon
        self.thumbnail = thumbnail
        self.kind = kind
    }

    public func replacingThumbnail(_ thumbnail: NSImage?) -> Self {
        Self(
            itemID: itemID,
            applicationIcon: applicationIcon,
            thumbnail: thumbnail,
            kind: kind
        )
    }
}

@MainActor
public protocol ClipboardVisualServing: AnyObject {
    func metadataVisual(for item: ClipboardItem) -> ClipboardVisualDescriptor
    func loadThumbnail(for item: ClipboardItem, maximumPixelSize: Int) async -> NSImage?
}
