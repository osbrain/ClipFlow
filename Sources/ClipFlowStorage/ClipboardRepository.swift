import ClipFlowCore
import CryptoKit
import Foundation

public struct RepositoryPayload: Equatable, Sendable {
    public let itemIndex: Int
    public let type: String
    public let data: Data
}

public final class ClipboardRepository: @unchecked Sendable {
    private let database: SQLCipherDatabase
    private let externalPayloadStore: ExternalPayloadStore
    private let externalThresholdBytes: Int

    public init(
        database: SQLCipherDatabase,
        externalPayloadStore: ExternalPayloadStore,
        externalThresholdBytes: Int
    ) throws {
        self.database = database
        self.externalPayloadStore = externalPayloadStore
        self.externalThresholdBytes = max(1, externalThresholdBytes)
        try Migrations.apply(to: database)
    }

    public func upsert(
        _ capture: NormalizedCapture,
        itemID: UUID? = nil,
        timestamp: Date = Date()
    ) throws -> ClipboardItem {
        let existing = try database.query(
            "SELECT id, created_at, is_favorite, last_used_at, custom_title FROM clipboard_items WHERE content_hash = ?;",
            bindings: [.text(capture.contentHash)]
        ).first
        let id = existing?.uuid("id") ?? itemID ?? UUID()
        let createdAt = existing?.date("created_at") ?? timestamp
        let now = timestamp
        let favorite = existing?.bool("is_favorite") ?? false
        let lastUsed = existing?.date("last_used_at")
        let customTitle = existing?.string("custom_title")

        let oldReferences = try externalReferences(for: id)
        var newReferences: [ExternalPayloadReference] = []
        var preparedPayloads: [(NormalizedPayload, Data?, ExternalPayloadReference?)] = []

        do {
            for payload in capture.payloads {
                if payload.data.count >= externalThresholdBytes {
                    let reference = try externalPayloadStore.write(payload.data, id: UUID())
                    newReferences.append(reference)
                    preparedPayloads.append((payload, nil, reference))
                } else {
                    preparedPayloads.append((payload, payload.data, nil))
                }
            }

            try database.transaction { database in
                try database.execute(
                    """
                    INSERT INTO clipboard_items(
                        id, created_at, updated_at, app_name, bundle_id, kind,
                        preview_text, search_text, byte_size, content_hash,
                        is_favorite, last_used_at, custom_title
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(content_hash) DO UPDATE SET
                        updated_at=excluded.updated_at,
                        app_name=excluded.app_name,
                        bundle_id=excluded.bundle_id,
                        kind=excluded.kind,
                        preview_text=excluded.preview_text,
                        search_text=excluded.search_text,
                        byte_size=excluded.byte_size;
                    """,
                    bindings: [
                        .text(id.uuidString), .real(createdAt.timeIntervalSince1970),
                        .real(now.timeIntervalSince1970), .text(capture.sourceAppName),
                        capture.sourceBundleID.map(SQLValue.text) ?? .null,
                        .text(capture.kind.rawValue), .text(capture.previewText),
                        .text(capture.searchText), .integer(Int64(capture.byteSize)),
                        .text(capture.contentHash), .integer(favorite ? 1 : 0),
                        lastUsed.map { .real($0.timeIntervalSince1970) } ?? .null,
                        customTitle.map(SQLValue.text) ?? .null
                    ]
                )
                try database.execute(
                    "DELETE FROM pasteboard_payloads WHERE item_id = ?;",
                    bindings: [.text(id.uuidString)]
                )
                for (payload, inlineData, reference) in preparedPayloads {
                    let digest = Data(SHA256.hash(data: payload.data))
                        .map { String(format: "%02x", $0) }.joined()
                    try database.execute(
                        """
                        INSERT INTO pasteboard_payloads(
                            item_id, item_index, type, inline_data,
                            external_file_name, byte_size, sha256
                        ) VALUES (?, ?, ?, ?, ?, ?, ?);
                        """,
                        bindings: [
                            .text(id.uuidString), .integer(Int64(payload.itemIndex)),
                            .text(payload.type), inlineData.map(SQLValue.blob) ?? .null,
                            reference.map { .text($0.fileName) } ?? .null,
                            .integer(Int64(payload.data.count)), .text(digest)
                        ]
                    )
                }
            }
        } catch {
            for reference in newReferences { try? externalPayloadStore.delete(reference) }
            throw error
        }

        for reference in oldReferences { try? externalPayloadStore.delete(reference) }
        return ClipboardItem(
            id: id, createdAt: createdAt, updatedAt: now,
            appName: capture.sourceAppName, bundleID: capture.sourceBundleID,
            kind: capture.kind, previewText: capture.previewText,
            searchText: capture.searchText, byteSize: capture.byteSize,
            contentHash: capture.contentHash, isFavorite: favorite,
            lastUsedAt: lastUsed, customTitle: customTitle,
            hasExternalPayload: !newReferences.isEmpty
        )
    }

    public func item(id: UUID) throws -> ClipboardItem? {
        try database.query(
            Self.itemSelect + " WHERE id = ? LIMIT 1;",
            bindings: [.text(id.uuidString)]
        ).first.flatMap(Self.decodeItem)
    }

    public func search(_ query: SearchQuery) throws -> [ClipboardItem] {
        let items = try database.query(
            Self.itemSelect + " ORDER BY COALESCE(last_used_at, updated_at) DESC, updated_at DESC;"
        ).compactMap(Self.decodeItem)

        var ranked: [(score: Int, item: ClipboardItem)] = []
        for item in items {
            let document = ItemSearchDocument(
                id: item.id,
                title: item.displayTitle,
                body: item.searchText,
                appName: item.appName,
                isFavorite: item.isFavorite,
                categoryIDs: Set(try categories(for: item.id).map(\.id)),
                kind: item.kind
            )
            if let score = query.score(document) {
                ranked.append((score: score, item: item))
            }
        }

        return ranked.sorted {
            if $0.score != $1.score { return $0.score < $1.score }
            return $0.item.updatedAt > $1.item.updatedAt
        }.map(\.item)
    }

    public func payloads(for itemID: UUID) throws -> [RepositoryPayload] {
        try database.query(
            """
            SELECT item_index, type, inline_data, external_file_name, byte_size, sha256
            FROM pasteboard_payloads WHERE item_id = ? ORDER BY item_index, type;
            """,
            bindings: [.text(itemID.uuidString)]
        ).map { row in
            let data: Data
            if let inline = row.data("inline_data") {
                data = inline
            } else if let fileName = row.string("external_file_name"),
                      let byteSize = row.integer("byte_size"),
                      let sha256 = row.string("sha256") {
                data = try externalPayloadStore.read(
                    ExternalPayloadReference(
                        fileName: fileName,
                        byteSize: Int(byteSize),
                        sha256: sha256
                    )
                )
            } else {
                throw SQLCipherDatabaseError.integrityFailed("Payload has no data source")
            }
            return RepositoryPayload(
                itemIndex: Int(row.integer("item_index") ?? 0),
                type: row.string("type") ?? "public.data",
                data: data
            )
        }
    }

    public func markUsed(_ id: UUID) throws {
        try database.execute(
            "UPDATE clipboard_items SET last_used_at = ?, updated_at = ? WHERE id = ?;",
            bindings: [
                .real(Date().timeIntervalSince1970),
                .real(Date().timeIntervalSince1970),
                .text(id.uuidString)
            ]
        )
    }

    public func setFavorite(_ favorite: Bool, for id: UUID) throws {
        try database.execute(
            "UPDATE clipboard_items SET is_favorite = ?, updated_at = ? WHERE id = ?;",
            bindings: [
                .integer(favorite ? 1 : 0),
                .real(Date().timeIntervalSince1970),
                .text(id.uuidString)
            ]
        )
    }

    public func rename(_ id: UUID, title: String?) throws {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedTitle = trimmed?.isEmpty == false ? trimmed : nil
        try database.execute(
            "UPDATE clipboard_items SET custom_title = ?, updated_at = ? WHERE id = ?;",
            bindings: [
                storedTitle.map(SQLValue.text) ?? .null,
                .real(Date().timeIntervalSince1970),
                .text(id.uuidString)
            ]
        )
    }

    public func delete(_ id: UUID) throws {
        let references = try externalReferences(for: id)
        try database.execute(
            "DELETE FROM clipboard_items WHERE id = ?;",
            bindings: [.text(id.uuidString)]
        )
        for reference in references {
            try? externalPayloadStore.delete(reference)
        }
    }

    public func createCategory(name: String) throws -> ClipCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SQLCipherDatabaseError.integrityFailed("Category name cannot be empty")
        }
        let category = ClipCategory(
            id: UUID(), name: trimmed, createdAt: Date(),
            sortOrder: Int(try database.query(
                "SELECT COUNT(*) AS count FROM clip_categories;"
            ).first?.integer("count") ?? 0)
        )
        try database.execute(
            "INSERT INTO clip_categories(id, name, created_at, sort_order) VALUES (?, ?, ?, ?);",
            bindings: [
                .text(category.id.uuidString), .text(category.name),
                .real(category.createdAt.timeIntervalSince1970),
                .integer(Int64(category.sortOrder))
            ]
        )
        return category
    }

    public func allCategories() throws -> [ClipCategory] {
        try database.query(
            "SELECT id, name, created_at, sort_order FROM clip_categories ORDER BY sort_order, created_at;"
        ).compactMap { row in
            guard let id = row.uuid("id"), let name = row.string("name"),
                  let createdAt = row.date("created_at") else { return nil }
            return ClipCategory(
                id: id, name: name, createdAt: createdAt,
                sortOrder: Int(row.integer("sort_order") ?? 0)
            )
        }
    }

    public func assign(itemID: UUID, categoryID: UUID) throws {
        try database.execute(
            "INSERT OR IGNORE INTO item_categories(item_id, category_id, created_at) VALUES (?, ?, ?);",
            bindings: [
                .text(itemID.uuidString), .text(categoryID.uuidString),
                .real(Date().timeIntervalSince1970)
            ]
        )
    }

    public func deleteCategory(_ id: UUID) throws {
        try database.execute(
            "DELETE FROM clip_categories WHERE id = ?;",
            bindings: [.text(id.uuidString)]
        )
    }

    public func categories(for itemID: UUID) throws -> [ClipCategory] {
        try database.query(
            """
            SELECT c.id, c.name, c.created_at, c.sort_order
            FROM clip_categories c JOIN item_categories ic ON ic.category_id = c.id
            WHERE ic.item_id = ? ORDER BY c.sort_order, c.created_at;
            """,
            bindings: [.text(itemID.uuidString)]
        ).compactMap { row in
            guard let id = row.uuid("id"), let name = row.string("name"),
                  let createdAt = row.date("created_at") else { return nil }
            return ClipCategory(
                id: id, name: name, createdAt: createdAt,
                sortOrder: Int(row.integer("sort_order") ?? 0)
            )
        }
    }

    @discardableResult
    public func reclassifyStoredItems(
        using normalizer: ClipboardNormalizer
    ) throws -> Int {
        let items = try database.query(
            Self.itemSelect + " ORDER BY created_at, id;"
        ).compactMap(Self.decodeItem)
        var updatedCount = 0

        for item in items {
            let storedPayloads = try payloads(for: item.id)
            let rawItems = Dictionary(grouping: storedPayloads, by: \.itemIndex)
                .sorted { $0.key < $1.key }
                .map { _, payloads in
                    RawClipboardItem(
                        representations: payloads.map {
                            RawClipboardRepresentation(type: $0.type, data: $0.data)
                        }
                    )
                }
            guard !rawItems.isEmpty else { continue }

            let normalized = try normalizer.normalize(
                RawClipboardCapture(
                    sourceAppName: item.appName,
                    sourceBundleID: item.bundleID,
                    items: rawItems
                )
            )
            guard normalized.kind != item.kind ||
                    normalized.previewText != item.previewText ||
                    normalized.searchText != item.searchText else {
                continue
            }

            try database.execute(
                """
                UPDATE clipboard_items
                SET kind = ?, preview_text = ?, search_text = ?
                WHERE id = ?;
                """,
                bindings: [
                    .text(normalized.kind.rawValue),
                    .text(normalized.previewText),
                    .text(normalized.searchText),
                    .text(item.id.uuidString)
                ]
            )
            updatedCount += 1
        }

        return updatedCount
    }

    private func externalReferences(for itemID: UUID) throws -> [ExternalPayloadReference] {
        try database.query(
            """
            SELECT external_file_name, byte_size, sha256 FROM pasteboard_payloads
            WHERE item_id = ? AND external_file_name IS NOT NULL;
            """,
            bindings: [.text(itemID.uuidString)]
        ).compactMap { row in
            guard let name = row.string("external_file_name"),
                  let size = row.integer("byte_size"),
                  let hash = row.string("sha256") else { return nil }
            return ExternalPayloadReference(fileName: name, byteSize: Int(size), sha256: hash)
        }
    }

    private static let itemSelect = """
        SELECT id, created_at, updated_at, app_name, bundle_id, kind,
               preview_text, search_text, byte_size, content_hash,
               is_favorite, last_used_at, custom_title,
               EXISTS(SELECT 1 FROM pasteboard_payloads p
                      WHERE p.item_id = clipboard_items.id AND p.external_file_name IS NOT NULL)
                   AS has_external_payload
        FROM clipboard_items
        """

    private static func decodeItem(_ row: SQLRow) -> ClipboardItem? {
        guard let id = row.uuid("id"), let createdAt = row.date("created_at"),
              let updatedAt = row.date("updated_at"), let appName = row.string("app_name"),
              let kindRaw = row.string("kind"), let kind = ClipboardKind(rawValue: kindRaw),
              let preview = row.string("preview_text"), let search = row.string("search_text"),
              let byteSize = row.integer("byte_size"), let hash = row.string("content_hash") else {
            return nil
        }
        return ClipboardItem(
            id: id, createdAt: createdAt, updatedAt: updatedAt,
            appName: appName, bundleID: row.string("bundle_id"), kind: kind,
            previewText: preview, searchText: search, byteSize: Int(byteSize),
            contentHash: hash, isFavorite: row.bool("is_favorite") ?? false,
            lastUsedAt: row.date("last_used_at"), customTitle: row.string("custom_title"),
            hasExternalPayload: row.bool("has_external_payload") ?? false
        )
    }
}

private extension SQLRow {
    func string(_ name: String) -> String? {
        guard case .text(let value) = self[name] else { return nil }
        return value
    }

    func integer(_ name: String) -> Int64? {
        guard case .integer(let value) = self[name] else { return nil }
        return value
    }

    func bool(_ name: String) -> Bool? {
        integer(name).map { $0 != 0 }
    }

    func data(_ name: String) -> Data? {
        guard case .blob(let value) = self[name] else { return nil }
        return value
    }

    func uuid(_ name: String) -> UUID? {
        string(name).flatMap(UUID.init(uuidString:))
    }

    func date(_ name: String) -> Date? {
        guard case .real(let value) = self[name] else { return nil }
        return Date(timeIntervalSince1970: value)
    }
}
