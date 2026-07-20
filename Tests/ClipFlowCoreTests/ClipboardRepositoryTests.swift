import CryptoKit
import Foundation
import Testing
import ClipFlowCore
@testable import ClipFlowStorage

@Suite("Encrypted clipboard repository")
struct ClipboardRepositoryTests {
    @Test("duplicate refresh preserves payloads and user metadata")
    func duplicateRefreshPreservesPayloadsAndUserMetadata() throws {
        let harness = try RepositoryHarness(externalThresholdBytes: 1)
        defer { harness.cleanup() }
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = firstDate.addingTimeInterval(120)
        let first = try harness.repository.upsert(
            harness.dataCapture(
                hash: "same",
                byteCount: 32,
                sourceAppName: "Notes",
                sourceBundleID: "com.apple.Notes",
                fillByte: 0x55
            ),
            timestamp: firstDate
        )
        try harness.repository.setFavorite(true, for: first.item.id)
        try harness.repository.rename(first.item.id, title: "Keep me")
        let category = try harness.repository.createCategory(name: "Work")
        try harness.repository.assign(itemID: first.item.id, categoryID: category.id)
        let externalFilesBefore = try harness.externalPayloadFileNames()
        let ignoredReplacementID = UUID()
        let second = try harness.repository.upsert(
            harness.dataCapture(
                hash: "same",
                byteCount: 32,
                sourceAppName: "Safari",
                sourceBundleID: "com.apple.Safari",
                fillByte: 0x66
            ),
            itemID: ignoredReplacementID,
            timestamp: secondDate
        )

        #expect(first.disposition == .inserted)
        #expect(second.disposition == .refreshed)
        #expect(first.item.id == second.item.id)
        #expect(second.item.id != ignoredReplacementID)
        #expect(second.item.updatedAt == secondDate)
        #expect(second.item.appName == "Safari")
        #expect(second.item.bundleID == "com.apple.Safari")
        #expect(second.item.previewText == first.item.previewText)
        #expect(second.item.isFavorite)
        #expect(second.item.customTitle == "Keep me")
        #expect(try harness.repository.categories(for: first.item.id).map(\.id) == [category.id])
        #expect(
            try harness.repository.payloads(for: first.item.id).first?.data
                == Data(repeating: 0x55, count: 32)
        )
        #expect(try harness.externalPayloadFileNames() == externalFilesBefore)
    }

    @Test("deleting a category does not delete its clipboard item")
    func categoryDeletionDoesNotDeleteClipboardItem() throws {
        let harness = try RepositoryHarness()
        defer { harness.cleanup() }

        let item = try harness.repository.upsert(
            harness.capture(hash: "a", preview: "A")
        )
        let category = try harness.repository.createCategory(name: "Work")
        try harness.repository.assign(itemID: item.item.id, categoryID: category.id)
        try harness.repository.deleteCategory(category.id)

        #expect(try harness.repository.item(id: item.item.id) != nil)
        #expect(try harness.repository.categories(for: item.item.id).isEmpty)
    }

    @Test("quick paste slots can be assigned replaced cleared and cascade with items")
    func quickPasteSlotsPersistAndCascade() throws {
        let harness = try RepositoryHarness()
        defer { harness.cleanup() }
        let first = try harness.repository.upsert(
            harness.capture(hash: "slot-first", preview: "First")
        )
        let second = try harness.repository.upsert(
            harness.capture(hash: "slot-second", preview: "Second")
        )

        try harness.repository.setQuickPasteSlot(1, itemID: first.item.id)
        try harness.repository.setQuickPasteSlot(1, itemID: second.item.id)
        try harness.repository.setQuickPasteSlot(2, itemID: first.item.id)

        #expect(try harness.repository.quickPasteSlots().map(\.index) == [1, 2])
        #expect(try harness.repository.quickPasteSlots().map(\.item.id) == [
            second.item.id, first.item.id
        ])

        try harness.repository.clearQuickPasteSlot(2)
        #expect(try harness.repository.quickPasteSlots().map(\.index) == [1])

        try harness.repository.delete(second.item.id)
        #expect(try harness.repository.quickPasteSlots().isEmpty)
    }

    @Test("paste stack preserves insertion order and cascades with deleted items")
    func pasteStackPersistsAndCascades() throws {
        let harness = try RepositoryHarness()
        defer { harness.cleanup() }
        let first = try harness.repository.upsert(
            harness.capture(hash: "stack-first", preview: "First")
        )
        let second = try harness.repository.upsert(
            harness.capture(hash: "stack-second", preview: "Second")
        )

        try harness.repository.appendToPasteStack(itemID: first.item.id)
        try harness.repository.appendToPasteStack(itemID: second.item.id)
        try harness.repository.appendToPasteStack(itemID: first.item.id)

        #expect(try harness.repository.pasteStackItems().map(\.item.id) == [
            first.item.id, second.item.id, first.item.id
        ])

        try harness.repository.removePasteStackItem(at: 2)
        #expect(try harness.repository.pasteStackItems().map(\.item.id) == [
            first.item.id, first.item.id
        ])

        try harness.repository.delete(first.item.id)
        #expect(try harness.repository.pasteStackItems().isEmpty)
    }

    @Test("recognized local text becomes searchable with the existing history query")
    func recognizedTextParticipatesInSearch() throws {
        let harness = try RepositoryHarness()
        defer { harness.cleanup() }
        let item = try harness.repository.upsert(
            harness.capture(hash: "ocr-image", preview: "Screenshot")
        )

        try harness.repository.updateRecognizedText("Invoice 2048", for: item.item.id)

        let results = try harness.repository.search(
            SearchQuery(text: "2048", categoryID: nil, kind: nil, favoritesOnly: false)
        )
        #expect(results.map(\.id) == [item.item.id])
        #expect(results.first?.recognizedText == "Invoice 2048")
    }

    @Test("expired temporary clips are removed before history search")
    func expiredTemporaryClipsArePurgedBeforeSearch() throws {
        let harness = try RepositoryHarness()
        defer { harness.cleanup() }
        let item = try harness.repository.upsert(
            harness.capture(hash: "temporary", preview: "Temporary")
        )

        try harness.repository.setTemporaryPolicy(
            for: item.item.id,
            expiresAt: Date.distantPast,
            isOneTime: false
        )

        #expect(try harness.repository.search(Self.emptyQuery).isEmpty)
        #expect(try harness.repository.item(id: item.item.id) == nil)
    }

    @Test("supplied timestamps persist and determine search order")
    func suppliedTimestampsPersistAndOrderResults() throws {
        let harness = try RepositoryHarness()
        defer { harness.cleanup() }
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = olderDate.addingTimeInterval(60)
        let olderID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
        let newerID = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!

        let older = try harness.repository.upsert(
            harness.capture(hash: "older", preview: "Older"),
            itemID: olderID,
            timestamp: olderDate
        )
        let newer = try harness.repository.upsert(
            harness.capture(hash: "newer", preview: "Newer"),
            itemID: newerID,
            timestamp: newerDate
        )
        let results = try harness.repository.search(
            SearchQuery(text: "", categoryID: nil, kind: nil, favoritesOnly: false)
        )

        #expect(older.item.id == olderID)
        #expect(older.item.createdAt == olderDate)
        #expect(older.item.updatedAt == olderDate)
        #expect(newer.item.id == newerID)
        #expect(newer.item.createdAt == newerDate)
        #expect(newer.item.updatedAt == newerDate)
        #expect(results.map(\.id).prefix(2) == [newer.item.id, older.item.id])
    }

    @Test("reclassifies stored Finder records without losing user metadata")
    func reclassifiesStoredFinderRecords() throws {
        let harness = try RepositoryHarness()
        defer { harness.cleanup() }
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let itemID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
        let fileURL = URL(fileURLWithPath: "/tmp/report.pdf")
        let original = try harness.repository.upsert(
            NormalizedCapture(
                sourceAppName: "Finder",
                sourceBundleID: "com.apple.finder",
                kind: .mixed,
                previewText: fileURL.path,
                searchText: fileURL.path.lowercased(),
                byteSize: fileURL.dataRepresentation.count + fileURL.path.utf8.count + 3,
                contentHash: "legacy-finder-hash",
                payloads: [
                    NormalizedPayload(
                        itemIndex: 0,
                        type: "public.file-url",
                        data: fileURL.dataRepresentation
                    ),
                    NormalizedPayload(
                        itemIndex: 0,
                        type: "public.utf8-plain-text",
                        data: Data(fileURL.path.utf8)
                    ),
                    NormalizedPayload(
                        itemIndex: 0,
                        type: "com.apple.finder.node",
                        data: Data([1, 2, 3])
                    )
                ]
            ),
            itemID: itemID,
            timestamp: timestamp
        )
        try harness.repository.setFavorite(true, for: itemID)
        try harness.repository.rename(itemID, title: "Quarterly Report")
        let category = try harness.repository.createCategory(name: "Work")
        try harness.repository.assign(itemID: itemID, categoryID: category.id)

        let updatedCount = try harness.repository.reclassifyStoredItems(
            using: ClipboardNormalizer(
                maxRepresentationBytes: 25 * 1_024 * 1_024,
                maxCaptureBytes: 100 * 1_024 * 1_024
            )
        )
        let fetched = try harness.repository.item(id: itemID)
        let repaired = try #require(fetched)

        #expect(updatedCount == 1)
        #expect(repaired.id == original.item.id)
        #expect(repaired.kind == .file)
        #expect(repaired.isFavorite)
        #expect(repaired.customTitle == "Quarterly Report")
        #expect(repaired.createdAt == timestamp)
        #expect(repaired.contentHash == "legacy-finder-hash")
        #expect(try harness.repository.categories(for: itemID).map(\.id) == [category.id])
    }

    @Test("updates the external payload threshold for future writes")
    func updatesExternalPayloadThreshold() throws {
        let harness = try RepositoryHarness(externalThresholdBytes: 1_000)
        defer { harness.cleanup() }

        harness.repository.updateExternalPayloadThreshold(bytes: 16)
        let item = try harness.repository.upsert(
            harness.dataCapture(hash: "threshold", byteCount: 16)
        )

        #expect(item.item.hasExternalPayload)
        #expect(try harness.repository.payloads(for: item.item.id).first?.data.count == 16)
    }

    @Test("retention deletes oldest non-favorites and their external payloads")
    func appliesRetentionAndCleansExternalPayloads() throws {
        let harness = try RepositoryHarness(externalThresholdBytes: 1)
        defer { harness.cleanup() }
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let favorite = try harness.repository.upsert(
            harness.dataCapture(hash: "favorite", byteCount: 32),
            timestamp: base
        )
        try harness.repository.setFavorite(true, for: favorite.item.id)
        let oldest = try harness.repository.upsert(
            harness.dataCapture(hash: "oldest", byteCount: 32),
            timestamp: base.addingTimeInterval(10)
        )
        let newest = try harness.repository.upsert(
            harness.dataCapture(hash: "newest", byteCount: 32),
            timestamp: base.addingTimeInterval(20)
        )

        let deleted = try harness.repository.applyRetention(
            RetentionPolicy(maxAge: nil, maxItemCount: 2, maxBytes: nil),
            now: base.addingTimeInterval(30)
        )

        #expect(deleted == [oldest.item.id])
        #expect(try harness.repository.item(id: oldest.item.id) == nil)
        #expect(try harness.repository.item(id: favorite.item.id) != nil)
        #expect(try harness.repository.item(id: newest.item.id) != nil)
        #expect(try harness.externalPayloadFileCount() == 2)
    }

    @Test("bounded search returns only the newest requested items")
    func boundedSearchReturnsNewestItems() throws {
        let harness = try RepositoryHarness()
        defer { harness.cleanup() }
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<600 {
            _ = try harness.repository.upsert(
                harness.capture(hash: "bounded-\(index)", preview: "Item \(index)"),
                timestamp: base.addingTimeInterval(TimeInterval(index))
            )
        }

        let results = try harness.repository.search(
            SearchQuery(text: "", categoryID: nil, kind: nil, favoritesOnly: false),
            limit: 200
        )

        #expect(results.count == 200)
        #expect(results.first?.previewText == "Item 599")
        #expect(results.last?.previewText == "Item 400")
    }

    @Test("search loads category memberships with one bulk query")
    func searchLoadsCategoriesInBulk() throws {
        let harness = try RepositoryHarness()
        defer { harness.cleanup() }
        for index in 0..<120 {
            _ = try harness.repository.upsert(
                harness.capture(hash: "category-\(index)", preview: "Item \(index)")
            )
        }
        let queryCounter = LockedCounter()
        harness.database.setQueryObserver { sql in
            if sql.contains("item_categories") {
                queryCounter.increment()
            }
        }

        _ = try harness.repository.search(
            SearchQuery(text: "", categoryID: nil, kind: nil, favoritesOnly: false),
            limit: 100
        )

        #expect(queryCounter.value == 1)
    }

    @Test("encrypted backup hides plaintext and imports with the correct password")
    func encryptedBackupRoundTripsWithPassword() throws {
        let source = try RepositoryHarness(externalThresholdBytes: 1)
        defer { source.cleanup() }
        let destination = try RepositoryHarness(externalThresholdBytes: 1)
        defer { destination.cleanup() }
        let inserted = try source.repository.upsert(
            source.dataCapture(
                hash: "backup-secret",
                byteCount: 48,
                sourceAppName: "Notes",
                sourceBundleID: "com.apple.Notes",
                fillByte: 0x73
            ),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try source.repository.setFavorite(true, for: inserted.item.id)
        try source.repository.rename(inserted.item.id, title: "Secret title")
        let category = try source.repository.createCategory(name: "Backups")
        try source.repository.assign(itemID: inserted.item.id, categoryID: category.id)
        try source.repository.setQuickPasteSlot(1, itemID: inserted.item.id)
        try source.repository.updateRecognizedText("Invoice 2048", for: inserted.item.id)

        let backup = try source.repository.exportEncryptedBackup(password: "correct horse")

        #expect(!String(decoding: backup, as: UTF8.self).contains("Secret title"))
        #expect(!String(decoding: backup, as: UTF8.self).contains("backup-secret"))

        let result = try destination.repository.importEncryptedBackup(
            backup,
            password: "correct horse"
        )
        let imported = try #require(destination.repository.search(Self.emptyQuery).first)

        #expect(result.insertedItemCount == 1)
        #expect(result.mergedItemCount == 0)
        #expect(imported.contentHash == "backup-secret")
        #expect(imported.isFavorite)
        #expect(imported.customTitle == "Secret title")
        #expect(imported.recognizedText == "Invoice 2048")
        #expect(try destination.repository.payloads(for: imported.id).first?.data.count == 48)
        #expect(try destination.repository.categories(for: imported.id).map(\.name) == ["Backups"])
        #expect(try destination.repository.quickPasteSlots().map(\.item.id) == [imported.id])
    }

    @Test("encrypted backup rejects wrong passwords before mutating the repository")
    func encryptedBackupRejectsWrongPasswordWithoutMutation() throws {
        let source = try RepositoryHarness()
        defer { source.cleanup() }
        let destination = try RepositoryHarness()
        defer { destination.cleanup() }
        _ = try source.repository.upsert(source.capture(hash: "safe", preview: "Safe"))
        let local = try destination.repository.upsert(
            destination.capture(hash: "local", preview: "Local")
        )
        let backup = try source.repository.exportEncryptedBackup(password: "right password")

        #expect(throws: ClipboardBackupError.self) {
            try destination.repository.importEncryptedBackup(backup, password: "wrong password")
        }

        let items = try destination.repository.search(Self.emptyQuery)
        #expect(items.map(\.id) == [local.item.id])
        #expect(items.map(\.contentHash) == ["local"])
    }

    @Test("encrypted backup rejects tampered KDF parameters before decrypting")
    func encryptedBackupRejectsTamperedKDFParameters() throws {
        let source = try RepositoryHarness()
        defer { source.cleanup() }
        let destination = try RepositoryHarness()
        defer { destination.cleanup() }
        _ = try source.repository.upsert(source.capture(hash: "safe", preview: "Safe"))
        let backup = try source.repository.exportEncryptedBackup(password: "right password")
        var envelope = try #require(
            JSONSerialization.jsonObject(with: backup) as? [String: Any]
        )
        envelope["iterations"] = 120_001
        let tampered = try JSONSerialization.data(withJSONObject: envelope)

        #expect(throws: ClipboardBackupError.invalidArchive) {
            try destination.repository.importEncryptedBackup(tampered, password: "right password")
        }

        #expect(try destination.repository.search(Self.emptyQuery).isEmpty)
    }

    @Test("encrypted backup rejects random salt generation failure")
    func encryptedBackupRejectsRandomSaltGenerationFailure() {
        #expect(throws: ClipboardBackupError.invalidArchive) {
            try EncryptedBackupCodec.randomData(byteCount: 16) { _, _ in
                errSecAllocate
            }
        }
    }

    @Test("encrypted backup import merges duplicates without replacing local payloads")
    func encryptedBackupImportMergesDuplicates() throws {
        let source = try RepositoryHarness()
        defer { source.cleanup() }
        let destination = try RepositoryHarness()
        defer { destination.cleanup() }
        let exported = try source.repository.upsert(
            source.capture(hash: "same-content", preview: "Exported payload")
        )
        try source.repository.setFavorite(true, for: exported.item.id)
        try source.repository.rename(exported.item.id, title: "Imported title")
        let backup = try source.repository.exportEncryptedBackup(password: "merge")

        let local = try destination.repository.upsert(
            destination.capture(hash: "same-content", preview: "Local payload")
        )
        let result = try destination.repository.importEncryptedBackup(backup, password: "merge")
        let item = try #require(try destination.repository.item(id: local.item.id))

        #expect(result.insertedItemCount == 0)
        #expect(result.mergedItemCount == 1)
        #expect(item.id == local.item.id)
        #expect(item.previewText == "Local payload")
        #expect(item.isFavorite)
        #expect(item.customTitle == "Imported title")
        #expect(
            String(
                decoding: try destination.repository.payloads(for: local.item.id).first?.data ?? Data(),
                as: UTF8.self
            ) == "Local payload"
        )
    }

    @Test("encrypted backup import keeps existing quick paste slots")
    func encryptedBackupImportDoesNotReplaceExistingQuickPasteSlots() throws {
        let source = try RepositoryHarness()
        defer { source.cleanup() }
        let destination = try RepositoryHarness()
        defer { destination.cleanup() }
        let exported = try source.repository.upsert(
            source.capture(hash: "exported-slot", preview: "Exported Slot")
        )
        try source.repository.setQuickPasteSlot(1, itemID: exported.item.id)
        let backup = try source.repository.exportEncryptedBackup(password: "slots")

        let local = try destination.repository.upsert(
            destination.capture(hash: "local-slot", preview: "Local Slot")
        )
        try destination.repository.setQuickPasteSlot(1, itemID: local.item.id)

        let result = try destination.repository.importEncryptedBackup(backup, password: "slots")
        let slots = try destination.repository.quickPasteSlots()

        #expect(result.restoredQuickPasteSlotCount == 0)
        #expect(slots.map(\.index) == [1])
        #expect(slots.map(\.item.id) == [local.item.id])
    }

    private static let emptyQuery = SearchQuery(
        text: "",
        categoryID: nil,
        kind: nil,
        favoritesOnly: false
    )
}

private final class RepositoryHarness {
    let root: URL
    let database: SQLCipherDatabase
    let repository: ClipboardRepository

    init(externalThresholdBytes: Int = 1_000) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        database = try SQLCipherDatabase(
            url: root.appendingPathComponent("ClipFlow.sqlite"),
            key: Data(repeating: 0x44, count: 32)
        )
        let payloadStore = ExternalPayloadStore(
            root: root.appendingPathComponent("Payloads", isDirectory: true),
            key: SymmetricKey(size: .bits256)
        )
        repository = try ClipboardRepository(
            database: database,
            externalPayloadStore: payloadStore,
            externalThresholdBytes: externalThresholdBytes
        )
    }

    func capture(hash: String, preview: String) -> NormalizedCapture {
        NormalizedCapture(
            sourceAppName: "Notes",
            sourceBundleID: "com.apple.Notes",
            kind: .text,
            previewText: preview,
            searchText: preview.lowercased(),
            byteSize: preview.utf8.count,
            contentHash: hash,
            payloads: [
                NormalizedPayload(
                    itemIndex: 0,
                    type: "public.utf8-plain-text",
                    data: Data(preview.utf8)
                )
            ]
        )
    }

    func dataCapture(
        hash: String,
        byteCount: Int,
        sourceAppName: String = "Test",
        sourceBundleID: String? = nil,
        fillByte: UInt8 = 0x55
    ) -> NormalizedCapture {
        NormalizedCapture(
            sourceAppName: sourceAppName,
            sourceBundleID: sourceBundleID,
            kind: .unknown,
            previewText: "Binary data",
            searchText: "binary data",
            byteSize: byteCount,
            contentHash: hash,
            payloads: [
                NormalizedPayload(
                    itemIndex: 0,
                    type: "public.data",
                    data: Data(repeating: fillByte, count: byteCount)
                )
            ]
        )
    }

    func externalPayloadFileNames() throws -> [String] {
        let directory = root.appendingPathComponent("Payloads", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent).sorted()
    }

    func externalPayloadFileCount() throws -> Int {
        let directory = root.appendingPathComponent("Payloads", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).count
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}
