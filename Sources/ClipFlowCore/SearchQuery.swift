import Foundation

public struct ItemSearchDocument: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let body: String
    public let appName: String
    public let isFavorite: Bool
    public let categoryIDs: Set<UUID>
    public let kind: ClipboardKind

    public init(
        id: UUID,
        title: String,
        body: String,
        appName: String,
        isFavorite: Bool,
        categoryIDs: Set<UUID> = [],
        kind: ClipboardKind = .unknown
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.appName = appName
        self.isFavorite = isFavorite
        self.categoryIDs = categoryIDs
        self.kind = kind
    }
}

public struct SearchQuery: Equatable, Sendable {
    public let text: String
    public let categoryID: UUID?
    public let kind: ClipboardKind?
    public let favoritesOnly: Bool

    public init(
        text: String,
        categoryID: UUID?,
        kind: ClipboardKind?,
        favoritesOnly: Bool
    ) {
        self.text = text
        self.categoryID = categoryID
        self.kind = kind
        self.favoritesOnly = favoritesOnly
    }

    public func score(_ document: ItemSearchDocument) -> Int? {
        guard !favoritesOnly || document.isFavorite else { return nil }
        guard categoryID.map(document.categoryIDs.contains) ?? true else { return nil }
        guard kind.map({ $0 == document.kind }) ?? true else { return nil }

        let normalizedQuery = Self.normalize(text)
        guard !normalizedQuery.isEmpty else { return 0 }

        let title = Self.normalize(document.title)
        let body = Self.normalize(document.body)
        let appName = Self.normalize(document.appName)

        if title == normalizedQuery {
            return 0
        }

        let tokens = normalizedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        var total = 0

        for token in tokens {
            if title.hasPrefix(token) {
                total += 10
            } else if title.contains(token) {
                total += 20
            } else if body.contains(token) {
                total += 30
            } else if appName.contains(token) {
                total += 40
            } else {
                return nil
            }
        }

        return total
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

