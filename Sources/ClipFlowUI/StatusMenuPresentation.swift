import AppKit
import ClipFlowCore
import Foundation

public struct StatusMenuRecentItem: Equatable, Sendable, Identifiable {
    public static let maximumMenuTitleWidth: CGFloat = 220

    public let id: UUID
    public let title: String
    public let sourceName: String
    public let kind: ClipboardKind

    public var symbolName: String {
        kind.presentation.symbolName
    }

    public var menuTitle: String {
        Self.truncatedMenuTitle(title)
    }

    public var menuTitleWidth: CGFloat {
        Self.renderedWidth(of: menuTitle)
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

    private static func truncatedMenuTitle(_ title: String) -> String {
        guard renderedWidth(of: title) > maximumMenuTitleWidth else {
            return title
        }

        let characters = Array(title)
        var lowerBound = 0
        var upperBound = characters.count

        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound + 1) / 2
            let candidate = String(characters.prefix(midpoint)) + "…"
            if renderedWidth(of: candidate) <= maximumMenuTitleWidth {
                lowerBound = midpoint
            } else {
                upperBound = midpoint - 1
            }
        }

        return String(characters.prefix(lowerBound)) + "…"
    }

    private static func renderedWidth(of title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [
            .font: NSFont.menuFont(ofSize: 0)
        ]).width
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

@MainActor
public enum StatusMenuPanelPresentation {
    public static func afterMenuCloses(_ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { @MainActor in
            action()
        }
    }
}
