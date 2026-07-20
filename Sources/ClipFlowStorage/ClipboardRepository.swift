import ClipFlowCore
import CryptoKit
import Foundation

public struct RepositoryPayload: Equatable, Sendable {
    public let itemIndex: Int
    public let type: String
    public let data: Data
}

public enum ClipboardUpsertDisposition: Equatable, Sendable {
    case inserted
    case refreshed
}

public struct ClipboardUpsertResult: Equatable, Sendable {
    public let item: ClipboardItem
    public let disposition: ClipboardUpsertDisposition

    public init(item: ClipboardItem, disposition: ClipboardUpsertDisposition) {
        self.item = item
        self.disposition = disposition
    }
}

public final class ClipboardRepository: @unchecked Sendable {
    private let database: SQLCipherDatabase
    private let externalPayloadStore: ExternalPayloadStore
    private let configurationLock = NSLock()
    private var configuredExternalThresholdBytes: Int

    public init(
        database: SQLCipherDatabase,
        externalPayloadStore: ExternalPayloadStore,
        externalThresholdBytes: Int
    ) throws {
        self.database = database
        self.externalPayloadStore = externalPayloadStore
        self.configuredExternalThresholdBytes = max(1, externalThresholdBytes)
        try Migrations.apply(to: database)
    }

    public func updateExternalPayloadThreshold(bytes: Int) {
        configurationLock.withLock {
            configuredExternalThresholdBytes = max(1, bytes)
        }
    }

    public func upsert(
        _ capture: NormalizedCapture,
        itemID: UUID? = nil,
        timestamp: Date = Date()
    ) throws -> ClipboardUpsertResult {
        if let existing = try database.query(
            Self.itemSelect + " WHERE content_hash = ? LIMIT 1;",
            bindings: [.text(capture.contentHash)]
        ).first.flatMap(Self.decodeItem) {
            try database.execute(
                """
                UPDATE clipboard_items
                SET updated_at = ?, app_name = ?, bundle_id = ?
                WHERE id = ?;
                """,
                bindings: [
                    .real(timestamp.timeIntervalSince1970),
                    .text(capture.sourceAppName),
                    capture.sourceBundleID.map(SQLValue.text) ?? .null,
                    .text(existing.id.uuidString)
                ]
            )
            return ClipboardUpsertResult(
                item: ClipboardItem(
                    id: existing.id,
                    createdAt: existing.createdAt,
                    updatedAt: timestamp,
                    appName: capture.sourceAppName,
                    bundleID: capture.sourceBundleID,
                    kind: existing.kind,
                    previewText: existing.previewText,
                    searchText: existing.searchText,
                    byteSize: existing.byteSize,
                    contentHash: existing.contentHash,
                    isFavorite: existing.isFavorite,
                    lastUsedAt: existing.lastUsedAt,
                    customTitle: existing.customTitle,
                    hasExternalPayload: existing.hasExternalPayload,
                    recognizedText: existing.recognizedText,
                    expiresAt: existing.expiresAt,
                    isOneTime: existing.isOneTime
                ),
                disposition: .refreshed
            )
        }

        let externalThresholdBytes = configurationLock.withLock {
            configuredExternalThresholdBytes
        }
        let id = itemID ?? UUID()
        let createdAt = timestamp
        let now = timestamp
        let favorite = false
        let lastUsed: Date? = nil
        let customTitle: String? = nil

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

        return ClipboardUpsertResult(
            item: ClipboardItem(
                id: id, createdAt: createdAt, updatedAt: now,
                appName: capture.sourceAppName, bundleID: capture.sourceBundleID,
                kind: capture.kind, previewText: capture.previewText,
                searchText: capture.searchText, byteSize: capture.byteSize,
                contentHash: capture.contentHash, isFavorite: favorite,
                lastUsedAt: lastUsed, customTitle: customTitle,
                hasExternalPayload: !newReferences.isEmpty
            ),
            disposition: .inserted
        )
    }

    public func item(id: UUID) throws -> ClipboardItem? {
        try database.query(
            Self.itemSelect + " WHERE id = ? LIMIT 1;",
            bindings: [.text(id.uuidString)]
        ).first.flatMap(Self.decodeItem)
    }

    public func search(
        _ query: SearchQuery,
        limit: Int = .max,
        offset: Int = 0
    ) throws -> [ClipboardItem] {
        try purgeExpiredTemporaryItems()
        let requestedLimit = max(1, limit)
        var conditions: [String] = []
        var bindings: [SQLValue] = []
        if query.favoritesOnly {
            conditions.append("is_favorite = 1")
        }
        if let kind = query.kind {
            conditions.append("kind = ?")
            bindings.append(.text(kind.rawValue))
        }
        if let categoryID = query.categoryID {
            conditions.append(
                "EXISTS(SELECT 1 FROM item_categories filter_categories "
                    + "WHERE filter_categories.item_id = clipboard_items.id "
                    + "AND filter_categories.category_id = ?)"
            )
            bindings.append(.text(categoryID.uuidString))
        }

        var sql = Self.itemSelect
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        sql += " ORDER BY COALESCE(last_used_at, updated_at) DESC, updated_at DESC"
        if query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           requestedLimit != .max {
            sql += " LIMIT ? OFFSET ?"
            bindings.append(.integer(Int64(requestedLimit)))
            bindings.append(.integer(Int64(max(0, offset))))
        }
        sql += ";"

        let items = try database.query(sql, bindings: bindings).compactMap(Self.decodeItem)
        let categoryIDsByItemID = try categoryIDsByItemID()

        var ranked: [(score: Int, item: ClipboardItem)] = []
        for item in items {
            let document = ItemSearchDocument(
                id: item.id,
                title: item.displayTitle,
                body: item.searchableText,
                appName: item.appName,
                isFavorite: item.isFavorite,
                categoryIDs: categoryIDsByItemID[item.id, default: []],
                kind: item.kind
            )
            if let score = query.score(document) {
                ranked.append((score: score, item: item))
            }
        }

        return ranked.sorted {
            if $0.score != $1.score { return $0.score < $1.score }
            return $0.item.updatedAt > $1.item.updatedAt
        }.dropFirst(max(0, offset)).prefix(requestedLimit).map(\.item)
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

    public func retentionCandidates() throws -> [RetentionCandidate] {
        try database.query(
            """
            SELECT id, COALESCE(last_used_at, updated_at) AS retention_timestamp,
                   byte_size, is_favorite
            FROM clipboard_items;
            """
        ).compactMap { row in
            guard let id = row.uuid("id"),
                  let timestamp = row.date("retention_timestamp"),
                  let byteSize = row.integer("byte_size") else {
                return nil
            }
            return RetentionCandidate(
                id: id,
                timestamp: timestamp,
                byteSize: Int(byteSize),
                isFavorite: row.bool("is_favorite") ?? false
            )
        }
    }

    @discardableResult
    public func applyRetention(
        _ policy: RetentionPolicy,
        now: Date = Date()
    ) throws -> [UUID] {
        let itemIDs = policy.cleanupCandidates(try retentionCandidates(), now: now)
        for id in itemIDs {
            try delete(id)
        }
        return itemIDs
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

    public func quickPasteSlots() throws -> [QuickPasteSlot] {
        let rows = try database.query(
            "SELECT slot_index, item_id FROM quick_paste_slots ORDER BY slot_index;"
        )
        return try rows.compactMap { row in
            guard let slotIndex = row.integer("slot_index"),
                  let itemID = row.uuid("item_id"),
                  let item = try item(id: itemID) else {
                return nil
            }
            return QuickPasteSlot(index: Int(slotIndex), item: item)
        }
    }

    public func setQuickPasteSlot(_ index: Int, itemID: UUID) throws {
        guard (1...9).contains(index) else {
            throw SQLCipherDatabaseError.integrityFailed(
                "Quick paste slot index must be between 1 and 9"
            )
        }
        let now = Date().timeIntervalSince1970
        try database.execute(
            """
            INSERT INTO quick_paste_slots(slot_index, item_id, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(slot_index) DO UPDATE SET
                item_id=excluded.item_id,
                updated_at=excluded.updated_at;
            """,
            bindings: [
                .integer(Int64(index)),
                .text(itemID.uuidString),
                .real(now),
                .real(now)
            ]
        )
    }

    public func clearQuickPasteSlot(_ index: Int) throws {
        try database.execute(
            "DELETE FROM quick_paste_slots WHERE slot_index = ?;",
            bindings: [.integer(Int64(index))]
        )
    }

    public func pasteStackItems() throws -> [PasteStackItem] {
        try database.query(
            """
            SELECT psi.position AS stack_position, ci.*
            FROM paste_stack_items psi
            JOIN clipboard_items ci ON ci.id = psi.item_id
            ORDER BY psi.position;
            """
        ).compactMap { row in
            guard let position = row.integer("stack_position"),
                  let item = Self.decodeItem(row) else {
                return nil
            }
            return PasteStackItem(position: Int(position), item: item)
        }
    }

    public func appendToPasteStack(itemID: UUID) throws {
        try database.execute(
            "INSERT INTO paste_stack_items(item_id, created_at) VALUES (?, ?);",
            bindings: [.text(itemID.uuidString), .real(Date().timeIntervalSince1970)]
        )
    }

    public func removePasteStackItem(at position: Int) throws {
        try database.execute(
            "DELETE FROM paste_stack_items WHERE position = ?;",
            bindings: [.integer(Int64(position))]
        )
    }

    public func clearPasteStack() throws {
        try database.execute("DELETE FROM paste_stack_items;")
    }

    public func templates() throws -> [SnippetTemplate] {
        try database.query(
            "SELECT id, title, body, created_at, updated_at FROM snippet_templates ORDER BY updated_at DESC;"
        ).compactMap { row in
            guard let id = row.uuid("id"),
                  let title = row.string("title"),
                  let body = row.string("body"),
                  let createdAt = row.date("created_at"),
                  let updatedAt = row.date("updated_at") else {
                return nil
            }
            return SnippetTemplate(
                id: id, title: title, body: body, createdAt: createdAt, updatedAt: updatedAt
            )
        }
    }

    @discardableResult
    public func createTemplate(title: String, body: String) throws -> SnippetTemplate {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty, !normalizedBody.isEmpty else {
            throw SQLCipherDatabaseError.integrityFailed("Template title and body cannot be empty")
        }
        let now = Date()
        let template = SnippetTemplate(
            id: UUID(), title: normalizedTitle, body: normalizedBody, createdAt: now, updatedAt: now
        )
        try database.execute(
            "INSERT INTO snippet_templates(id, title, body, created_at, updated_at) VALUES (?, ?, ?, ?, ?);",
            bindings: [
                .text(template.id.uuidString), .text(template.title), .text(template.body),
                .real(now.timeIntervalSince1970), .real(now.timeIntervalSince1970)
            ]
        )
        return template
    }

    public func updateRecognizedText(_ text: String, for itemID: UUID) throws {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        try database.execute(
            "UPDATE clipboard_items SET ocr_text = ? WHERE id = ?;",
            bindings: [
                normalized.isEmpty ? .null : .text(normalized),
                .text(itemID.uuidString)
            ]
        )
    }

    public func setTemporaryPolicy(
        for itemID: UUID,
        expiresAt: Date?,
        isOneTime: Bool
    ) throws {
        try database.execute(
            "UPDATE clipboard_items SET expires_at = ?, is_one_time = ? WHERE id = ?;",
            bindings: [
                expiresAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                .integer(isOneTime ? 1 : 0),
                .text(itemID.uuidString)
            ]
        )
    }

    private func purgeExpiredTemporaryItems(now: Date = Date()) throws {
        let expiredIDs = try database.query(
            "SELECT id FROM clipboard_items WHERE expires_at IS NOT NULL AND expires_at <= ?;",
            bindings: [.real(now.timeIntervalSince1970)]
        ).compactMap { $0.uuid("id") }
        for id in expiredIDs {
            try delete(id)
        }
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

    private func categoryIDsByItemID() throws -> [UUID: Set<UUID>] {
        let rows = try database.query(
            "SELECT item_id, category_id FROM item_categories;"
        )
        var result: [UUID: Set<UUID>] = [:]
        for row in rows {
            guard let itemID = row.uuid("item_id"),
                  let categoryID = row.uuid("category_id") else {
                continue
            }
            result[itemID, default: []].insert(categoryID)
        }
        return result
    }

    @discardableResult
    public func reclassifyStoredItems(
        using normalizer: ClipboardNormalizer
    ) throws -> Int {
        let items = try database.query(
            Self.itemSelect + " ORDER BY created_at, id;"
        ).compactMap(Self.decodeItem).filter { !$0.isOneTime && $0.expiresAt == nil }
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
               is_favorite, last_used_at, custom_title, ocr_text, expires_at, is_one_time,
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
            hasExternalPayload: row.bool("has_external_payload") ?? false,
            recognizedText: row.string("ocr_text"),
            expiresAt: row.date("expires_at"),
            isOneTime: row.bool("is_one_time") ?? false
        )
    }
}

public extension ClipboardRepository {
    func exportEncryptedBackup(password: String) throws -> Data {
        let items = try database.query(
            Self.itemSelect + " ORDER BY created_at, id;"
        ).compactMap(Self.decodeItem)
        let backupItems = try items.map { item in
            ClipboardBackupItem(
                id: item.id,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                appName: item.appName,
                bundleID: item.bundleID,
                kind: item.kind,
                previewText: item.previewText,
                searchText: item.searchText,
                byteSize: item.byteSize,
                contentHash: item.contentHash,
                isFavorite: item.isFavorite,
                lastUsedAt: item.lastUsedAt,
                customTitle: item.customTitle,
                recognizedText: item.recognizedText,
                payloads: try payloads(for: item.id).map {
                    ClipboardBackupPayload(
                        itemIndex: $0.itemIndex,
                        type: $0.type,
                        data: $0.data
                    )
                }
            )
        }
        let categories = try allCategories().map {
            ClipboardBackupCategory(
                id: $0.id,
                name: $0.name,
                createdAt: $0.createdAt,
                sortOrder: $0.sortOrder
            )
        }
        let itemCategories = try itemCategoryPairs().map {
            ClipboardBackupItemCategory(itemID: $0.itemID, categoryID: $0.categoryID)
        }
        let slots = try quickPasteSlots().map {
            ClipboardBackupQuickPasteSlot(index: $0.index, itemID: $0.item.id)
        }
        let document = ClipboardBackupDocument(
            version: EncryptedBackupCodec.currentVersion,
            exportedAt: Date(),
            items: backupItems,
            categories: categories,
            itemCategories: itemCategories,
            quickPasteSlots: slots
        )
        return try EncryptedBackupCodec.seal(document, password: password)
    }

    @discardableResult
    func importEncryptedBackup(
        _ data: Data,
        password: String
    ) throws -> ClipboardBackupImportResult {
        let document = try EncryptedBackupCodec.open(data, password: password)
        let existingItems = try itemsByContentHash()
        let existingCategories = try categoriesByName()
        let thresholdBytes = configurationLock.withLock {
            configuredExternalThresholdBytes
        }
        var occupiedQuickPasteSlots = Set(try quickPasteSlots().map(\.index))

        var preparedItems: [PreparedBackupItem] = []
        var newReferences: [ExternalPayloadReference] = []
        do {
            for backupItem in document.items where existingItems[backupItem.contentHash] == nil {
                var preparedPayloads: [PreparedBackupPayload] = []
                for payload in backupItem.payloads {
                    if payload.data.count >= thresholdBytes {
                        let reference = try externalPayloadStore.write(payload.data, id: UUID())
                        newReferences.append(reference)
                        preparedPayloads.append(
                            PreparedBackupPayload(
                                payload: payload,
                                inlineData: nil,
                                reference: reference
                            )
                        )
                    } else {
                        preparedPayloads.append(
                            PreparedBackupPayload(
                                payload: payload,
                                inlineData: payload.data,
                                reference: nil
                            )
                        )
                    }
                }
                preparedItems.append(
                    PreparedBackupItem(item: backupItem, payloads: preparedPayloads)
                )
            }

            var insertedItemCount = 0
            var mergedItemCount = 0
            var createdCategoryCount = 0
            var restoredQuickPasteSlotCount = 0
            try database.transaction { database in
                var targetItemIDsByBackupID: [UUID: UUID] = [:]
                var targetCategoryIDsByBackupID: [UUID: UUID] = [:]
                var categoryNames = existingCategories

                for item in document.items {
                    if let existing = existingItems[item.contentHash] {
                        targetItemIDsByBackupID[item.id] = existing.id
                        try mergeMetadata(from: item, into: existing.id, database: database)
                        mergedItemCount += 1
                    }
                }

                for prepared in preparedItems {
                    let item = prepared.item
                    try insertImportedItem(prepared, database: database)
                    targetItemIDsByBackupID[item.id] = item.id
                    insertedItemCount += 1
                }

                for category in document.categories {
                    if let existingID = categoryNames[category.name] {
                        targetCategoryIDsByBackupID[category.id] = existingID
                    } else {
                        try database.execute(
                            """
                            INSERT INTO clip_categories(id, name, created_at, sort_order)
                            VALUES (?, ?, ?, ?);
                            """,
                            bindings: [
                                .text(category.id.uuidString),
                                .text(category.name),
                                .real(category.createdAt.timeIntervalSince1970),
                                .integer(Int64(category.sortOrder))
                            ]
                        )
                        categoryNames[category.name] = category.id
                        targetCategoryIDsByBackupID[category.id] = category.id
                        createdCategoryCount += 1
                    }
                }

                for link in document.itemCategories {
                    guard let itemID = targetItemIDsByBackupID[link.itemID],
                          let categoryID = targetCategoryIDsByBackupID[link.categoryID] else {
                        continue
                    }
                    try database.execute(
                        """
                        INSERT OR IGNORE INTO item_categories(item_id, category_id, created_at)
                        VALUES (?, ?, ?);
                        """,
                        bindings: [
                            .text(itemID.uuidString),
                            .text(categoryID.uuidString),
                            .real(Date().timeIntervalSince1970)
                        ]
                    )
                }

                for slot in document.quickPasteSlots {
                    guard (1...9).contains(slot.index),
                          !occupiedQuickPasteSlots.contains(slot.index),
                          let itemID = targetItemIDsByBackupID[slot.itemID] else {
                        continue
                    }
                    let now = Date().timeIntervalSince1970
                    try database.execute(
                        """
                        INSERT INTO quick_paste_slots(slot_index, item_id, created_at, updated_at)
                        VALUES (?, ?, ?, ?);
                        """,
                        bindings: [
                            .integer(Int64(slot.index)),
                            .text(itemID.uuidString),
                            .real(now),
                            .real(now)
                        ]
                    )
                    occupiedQuickPasteSlots.insert(slot.index)
                    restoredQuickPasteSlotCount += 1
                }
            }
            return ClipboardBackupImportResult(
                insertedItemCount: insertedItemCount,
                mergedItemCount: mergedItemCount,
                createdCategoryCount: createdCategoryCount,
                restoredQuickPasteSlotCount: restoredQuickPasteSlotCount
            )
        } catch {
            for reference in newReferences { try? externalPayloadStore.delete(reference) }
            throw error
        }
    }

    private func itemCategoryPairs() throws -> [(itemID: UUID, categoryID: UUID)] {
        try database.query(
            "SELECT item_id, category_id FROM item_categories ORDER BY item_id, category_id;"
        ).compactMap { row in
            guard let itemID = row.uuid("item_id"),
                  let categoryID = row.uuid("category_id") else {
                return nil
            }
            return (itemID, categoryID)
        }
    }

    private func itemsByContentHash() throws -> [String: ClipboardItem] {
        let items = try database.query(
            Self.itemSelect + " ORDER BY created_at, id;"
        ).compactMap(Self.decodeItem)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.contentHash, $0) })
    }

    private func categoriesByName() throws -> [String: UUID] {
        Dictionary(uniqueKeysWithValues: try allCategories().map { ($0.name, $0.id) })
    }

    private func mergeMetadata(
        from item: ClipboardBackupItem,
        into itemID: UUID,
        database: SQLCipherDatabase
    ) throws {
        let title = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let recognizedText = item.recognizedText?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        try database.execute(
            """
            UPDATE clipboard_items
            SET is_favorite = CASE WHEN ? = 1 THEN 1 ELSE is_favorite END,
                custom_title = CASE
                    WHEN custom_title IS NULL AND ? IS NOT NULL THEN ?
                    ELSE custom_title
                END,
                ocr_text = CASE
                    WHEN ocr_text IS NULL AND ? IS NOT NULL THEN ?
                    ELSE ocr_text
                END
            WHERE id = ?;
            """,
            bindings: [
                .integer(item.isFavorite ? 1 : 0),
                title?.isEmpty == false ? .text(title!) : .null,
                title?.isEmpty == false ? .text(title!) : .null,
                recognizedText?.isEmpty == false ? .text(recognizedText!) : .null,
                recognizedText?.isEmpty == false ? .text(recognizedText!) : .null,
                .text(itemID.uuidString)
            ]
        )
    }

    private func insertImportedItem(
        _ prepared: PreparedBackupItem,
        database: SQLCipherDatabase
    ) throws {
        let item = prepared.item
        try database.execute(
            """
            INSERT INTO clipboard_items(
                id, created_at, updated_at, app_name, bundle_id, kind,
                preview_text, search_text, byte_size, content_hash,
                is_favorite, last_used_at, custom_title, ocr_text
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(item.id.uuidString),
                .real(item.createdAt.timeIntervalSince1970),
                .real(item.updatedAt.timeIntervalSince1970),
                .text(item.appName),
                item.bundleID.map(SQLValue.text) ?? .null,
                .text(item.kind.rawValue),
                .text(item.previewText),
                .text(item.searchText),
                .integer(Int64(item.byteSize)),
                .text(item.contentHash),
                .integer(item.isFavorite ? 1 : 0),
                item.lastUsedAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                item.customTitle.map(SQLValue.text) ?? .null,
                item.recognizedText.map(SQLValue.text) ?? .null
            ]
        )

        for preparedPayload in prepared.payloads {
            let payload = preparedPayload.payload
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
                    .text(item.id.uuidString),
                    .integer(Int64(payload.itemIndex)),
                    .text(payload.type),
                    preparedPayload.inlineData.map(SQLValue.blob) ?? .null,
                    preparedPayload.reference.map { .text($0.fileName) } ?? .null,
                    .integer(Int64(payload.data.count)),
                    .text(digest)
                ]
            )
        }
    }
}

private struct PreparedBackupItem {
    let item: ClipboardBackupItem
    let payloads: [PreparedBackupPayload]
}

private struct PreparedBackupPayload {
    let payload: ClipboardBackupPayload
    let inlineData: Data?
    let reference: ExternalPayloadReference?
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
