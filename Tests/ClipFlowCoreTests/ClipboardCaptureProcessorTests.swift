import Foundation
import Testing
import ClipFlowCore
import ClipFlowStorage
import ClipFlowSystem
@testable import ClipFlowUI

@Suite("Clipboard capture processing")
@MainActor
struct ClipboardCaptureProcessorTests {
    @Test("duplicate capture skips retention and full model reload")
    func duplicateCaptureUsesIncrementalRefresh() async {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let item = Self.item(updatedAt: base, appName: "Notes")
        let refreshed = Self.item(
            id: item.id,
            updatedAt: base.addingTimeInterval(60),
            appName: "Safari"
        )
        let repository = CaptureTestRepository(items: [item])
        repository.nextUpsertResult = ClipboardUpsertResult(
            item: refreshed,
            disposition: .refreshed
        )
        let model = AppModel(repository: repository, pasteService: CaptureTestPasteService())
        await model.reload()
        let processor = ClipboardCaptureProcessor(
            normalizer: Self.normalizer,
            repository: repository,
            model: model,
            retentionPolicy: { RetentionPolicy(maxAge: nil, maxItemCount: 500, maxBytes: nil) }
        )

        let outcome = await processor.process(Self.rawCapture)

        #expect(outcome == .refreshedIncrementally)
        #expect(repository.searchCount == 1)
        #expect(repository.retentionCount == 0)
        #expect(model.items.first?.appName == "Safari")
    }

    @Test("new capture applies retention and reloads the model")
    func insertedCaptureAppliesRetentionAndReloads() async {
        let item = Self.item(updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let repository = CaptureTestRepository(items: [])
        repository.nextUpsertResult = ClipboardUpsertResult(
            item: item,
            disposition: .inserted
        )
        repository.replaceItems(with: [item])
        let model = AppModel(repository: repository, pasteService: CaptureTestPasteService())
        await model.reload()
        let processor = ClipboardCaptureProcessor(
            normalizer: Self.normalizer,
            repository: repository,
            model: model,
            retentionPolicy: { RetentionPolicy(maxAge: nil, maxItemCount: 500, maxBytes: nil) }
        )

        let outcome = await processor.process(Self.rawCapture)

        #expect(outcome == .inserted)
        #expect(repository.searchCount == 2)
        #expect(repository.retentionCount == 1)
        #expect(model.items.map(\.id) == [item.id])
    }

    private static let normalizer = ClipboardNormalizer(
        maxRepresentationBytes: 1_000,
        maxCaptureBytes: 2_000
    )

    private static let rawCapture = RawClipboardCapture(
        sourceAppName: "Notes",
        sourceBundleID: "com.apple.Notes",
        items: [
            RawClipboardItem(representations: [
                RawClipboardRepresentation(
                    type: "public.utf8-plain-text",
                    data: Data("Captured".utf8)
                )
            ])
        ]
    )

    private static func item(
        id: UUID = UUID(),
        updatedAt: Date,
        appName: String = "Notes"
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            createdAt: .distantPast,
            updatedAt: updatedAt,
            appName: appName,
            bundleID: "local.clipflow.tests",
            kind: .text,
            previewText: "Captured",
            searchText: "captured",
            byteSize: 8,
            contentHash: "stable-hash",
            isFavorite: false,
            lastUsedAt: nil,
            customTitle: nil,
            hasExternalPayload: false
        )
    }
}

private final class CaptureTestRepository:
    HistoryRepository,
    ClipboardCaptureRepository,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var items: [ClipboardItem]
    private var searches = 0
    private var retentions = 0
    var nextUpsertResult: ClipboardUpsertResult?

    init(items: [ClipboardItem]) {
        self.items = items
    }

    var searchCount: Int { lock.withLock { searches } }
    var retentionCount: Int { lock.withLock { retentions } }

    func replaceItems(with items: [ClipboardItem]) {
        lock.withLock { self.items = items }
    }

    func search(_ query: SearchQuery, limit: Int) throws -> [ClipboardItem] {
        lock.withLock {
            searches += 1
            return Array(items.prefix(limit))
        }
    }

    func upsert(
        _ capture: NormalizedCapture,
        itemID: UUID?,
        timestamp: Date
    ) throws -> ClipboardUpsertResult {
        try lock.withLock {
            guard let nextUpsertResult else { throw CaptureTestError.missingResult }
            return nextUpsertResult
        }
    }

    func applyRetention(_ policy: RetentionPolicy, now: Date) throws -> [UUID] {
        lock.withLock {
            retentions += 1
            return []
        }
    }

    func markUsed(_ id: UUID) throws {}
    func setFavorite(_ favorite: Bool, for id: UUID) throws {}
    func rename(_ id: UUID, title: String?) throws {}
    func delete(_ id: UUID) throws {}
    func allCategories() throws -> [ClipCategory] { [] }
    func createCategory(name: String) throws -> ClipCategory { throw CaptureTestError.unsupported }
    func assign(itemID: UUID, categoryID: UUID) throws {}
    func deleteCategory(_ id: UUID) throws {}
}

private actor CaptureTestPasteService: PasteServing {
    func paste(item: ClipboardItem) async throws -> PasteOutcome { .pasted }
}

private enum CaptureTestError: Error {
    case missingResult
    case unsupported
}
