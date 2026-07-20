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
    public let recognizedText: String?
    public let expiresAt: Date?
    public let isOneTime: Bool

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
        hasExternalPayload: Bool,
        recognizedText: String? = nil,
        expiresAt: Date? = nil,
        isOneTime: Bool = false
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
        self.recognizedText = recognizedText
        self.expiresAt = expiresAt
        self.isOneTime = isOneTime
    }

    public var displayTitle: String {
        guard let customTitle, !customTitle.isEmpty else {
            return previewText
        }
        return customTitle
    }

    public var searchableText: String {
        [searchText, recognizedText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    public var isExpired: Bool {
        expiresAt.map { $0 <= Date() } ?? false
    }
}

public struct ClipCategory: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public let sortOrder: Int

    public init(id: UUID, name: String, createdAt: Date, sortOrder: Int) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}

public struct QuickPasteSlot: Identifiable, Codable, Equatable, Sendable {
    public let index: Int
    public let item: ClipboardItem

    public init(index: Int, item: ClipboardItem) {
        self.index = index
        self.item = item
    }

    public var id: Int { index }
}

public struct PasteStackItem: Identifiable, Codable, Equatable, Sendable {
    public let position: Int
    public let item: ClipboardItem

    public init(position: Int, item: ClipboardItem) {
        self.position = position
        self.item = item
    }

    public var id: Int { position }
}
