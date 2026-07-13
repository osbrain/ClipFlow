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
        let second = try harness.repository.upsert(
            harness.capture(hash: "same", preview: "Second")
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
}

private final class RepositoryHarness {
    let root: URL
    let repository: ClipboardRepository

    init() throws {
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
            externalThresholdBytes: 1_000
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

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
