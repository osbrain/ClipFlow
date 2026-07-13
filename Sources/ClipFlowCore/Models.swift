import Foundation

public enum ClipboardKind: String, Codable, Sendable {
    case text
    case richText
    case image
    case file
    case link
    case mixed
    case unknown
}

public struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let appName: String
    public let bundleID: String?
    public let kind: ClipboardKind
    public let previewText: String
    public let searchText: String
    public let byteSize: Int
    public let contentHash: String
    public let isFavorite: Bool
    public let lastUsedAt: Date?
    public let customTitle: String?
    public let hasExternalPayload: Bool

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        appName: String,
        bundleID: String?,
        kind: ClipboardKind,
        previewText: String,
        searchText: String,
        byteSize: Int,
        contentHash: String,
        isFavorite: Bool,
        lastUsedAt: Date?,
        customTitle: String?,
        hasExternalPayload: Bool
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.appName = appName
        self.bundleID = bundleID
        self.kind = kind
        self.previewText = previewText
        self.searchText = searchText
        self.byteSize = byteSize
        self.contentHash = contentHash
        self.isFavorite = isFavorite
        self.lastUsedAt = lastUsedAt
        self.customTitle = customTitle
        self.hasExternalPayload = hasExternalPayload
    }

    public var displayTitle: String {
        guard let customTitle, !customTitle.isEmpty else {
            return previewText
        }
        return customTitle
    }
}

