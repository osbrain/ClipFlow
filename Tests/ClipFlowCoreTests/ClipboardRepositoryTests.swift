import CryptoKit
import Foundation
import Testing
import ClipFlowCore
@testable import ClipFlowStorage

@Suite("Encrypted clipboard repository")
struct ClipboardRepositoryTests {
    @Test("deduplicates by hash and searches the updated item")
    func insertDeduplicatesByHashAndSearchesUpdatedItem() throws {
        let harness = try RepositoryHarness()
        defer { harness.cleanup() }

        let first = try harness.repository.upsert(
            harness.capture(hash: "same", preview: "First")
        )
        let ignoredReplacementID = UUID()
        let second = try harness.repository.upsert(
            harness.capture(hash: "same", preview: "Second"),
            itemID: ignoredReplacementID
        )
        let results = try harness.repository.search(
            SearchQuery(
                text: "Second",
                categoryID: nil,
                kind: nil,
                favoritesOnly: false
            )
        )

        #expect(first.id == second.id)
        #expect(second.id != ignoredReplacementID)
        #expect(results.map(\.id) == [first.id])
        #expect(try harness.repository.payloads(for: first.id).first?.data == Data("Second".utf8))
    }

    @Test("deleting a category does not delete its clipboard item")
    func categoryDeletionDoesNotDeleteClipboardItem() throws {
        let harness = try RepositoryHarness()
        defer { harness.cleanup() }

        let item = try harness.repository.upsert(
            harness.capture(hash: "a", preview: "A")
        )
        let category = try harness.repository.createCategory(name: "Work")
        try harness.repository.assign(itemID: item.id, categoryID: category.id)
        try harness.repository.deleteCategory(category.id)

        #expect(try harness.repository.item(id: item.id) != nil)
        #expect(try harness.repository.categories(for: item.id).isEmpty)
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

        #expect(older.id == olderID)
        #expect(older.createdAt == olderDate)
        #expect(older.updatedAt == olderDate)
        #expect(newer.id == newerID)
        #expect(newer.createdAt == newerDate)
        #expect(newer.updatedAt == newerDate)
        #expect(results.map(\.id).prefix(2) == [newer.id, older.id])
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
        #expect(repaired.id == original.id)
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

        #expect(item.hasExternalPayload)
        #expect(try harness.repository.payloads(for: item.id).first?.data.count == 16)
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
        try harness.repository.setFavorite(true, for: favorite.id)
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

        #expect(deleted == [oldest.id])
        #expect(try harness.repository.item(id: oldest.id) == nil)
        #expect(try harness.repository.item(id: favorite.id) != nil)
        #expect(try harness.repository.item(id: newest.id) != nil)
        #expect(try harness.externalPayloadFileCount() == 2)
    }
}

private final class RepositoryHarness {
    let root: URL
    let repository: ClipboardRepository

    init(externalThresholdBytes: Int = 1_000) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let database = try SQLCipherDatabase(
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

    func dataCapture(hash: String, byteCount: Int) -> NormalizedCapture {
        NormalizedCapture(
            sourceAppName: "Test",
            sourceBundleID: nil,
            kind: .unknown,
            previewText: "Binary data",
            searchText: "binary data",
            byteSize: byteCount,
            contentHash: hash,
            payloads: [
                NormalizedPayload(
                    itemIndex: 0,
                    type: "public.data",
                    data: Data(repeating: 0x55, count: byteCount)
                )
            ]
        )
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
