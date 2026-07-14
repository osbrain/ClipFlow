import ClipFlowCore
import Foundation

public struct StatusMenuRecentItem: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let sourceName: String
    public let kind: ClipboardKind

    public var symbolName: String {
        kind.presentation.symbolName
    }

    init(item: ClipboardItem) {
        id = item.id
        sourceName = item.appName
        kind = item.kind

        let compactTitle = item.displayTitle
            .split(whereSeparator: \ .isWhitespace)
            .joined(separator: " ")
        title = compactTitle.isEmpty ? item.appName : compactTitle
    }
}

public struct StatusMenuPresentation: Equatable, Sendable {
    public static let maximumRecentItems = 3

    public let recordCount: Int
    public let recentItems: [StatusMenuRecentItem]
    public let pasteDestinationName: String?

    public init(
        items: [ClipboardItem],
        pasteDestinationName: String?
    ) {
        recordCount = items.count
        recentItems = items.prefix(Self.maximumRecentItems).map(StatusMenuRecentItem.init)
        self.pasteDestinationName = pasteDestinationName
    }
}
