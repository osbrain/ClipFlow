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

    @Test("privacy policy can ignore a capture before it reaches storage")
    func privacyPolicyIgnoresCaptureBeforeStorage() async {
        let repository = CaptureTestRepository(items: [])
        let model = AppModel(repository: repository, pasteService: CaptureTestPasteService())
        await model.reload()
        let processor = ClipboardCaptureProcessor(
            normalizer: Self.normalizer,
            repository: repository,
            model: model,
            retentionPolicy: { RetentionPolicy(maxAge: nil, maxItemCount: 500, maxBytes: nil) },
            privacyPolicy: {
                PrivacyCapturePolicy(
                    excludedAppIdentifiers: ["com.apple.Notes"],
                    excludedContentPatterns: [],
                    ignoresSensitiveText: false
                )
            }
        )

        let outcome = await processor.process(Self.rawCapture)

        #expect(outcome == .ignoredByPrivacy)
        #expect(repository.upsertCount == 0)
        #expect(repository.retentionCount == 0)
        #expect(repository.searchCount == 1)
    }

    @Test("inserted captures can be assigned to a smart category before reload")
    func insertedCapturesCanBeSmartCategorized() async {
        let item = Self.item(
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            preview: "func paste() { return true }"
        )
        let repository = CaptureTestRepository(items: [])
        repository.nextUpsertResult = ClipboardUpsertResult(
            item: item,
            disposition: .inserted
        )
        let model = AppModel(repository: repository, pasteService: CaptureTestPasteService())
        await model.reload()
        let processor = ClipboardCaptureProcessor(
            normalizer: Self.normalizer,
            repository: repository,
            model: model,
            retentionPolicy: { RetentionPolicy(maxAge: nil, maxItemCount: 500, maxBytes: nil) },
            smartCategoryPolicy: { SmartCategoryPolicy(isEnabled: true) }
        )

        let outcome = await processor.process(Self.rawCapture(text: "func paste() { return true }"))

        #expect(outcome == .inserted)
        #expect(repository.createdCategoryNames == [SmartCategory.code.localizedName])
        #expect(repository.assignedCategoryNames == [SmartCategory.code.localizedName])
        #expect(repository.searchCount == 2)
    }

    @Test("refreshed captures skip smart categorization")
    func refreshedCapturesSkipSmartCategorization() async {
        let item = Self.item(updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let refreshed = Self.item(
            id: item.id,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_060),
            appName: "Notes"
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
            retentionPolicy: { RetentionPolicy(maxAge: nil, maxItemCount: 500, maxBytes: nil) },
            smartCategoryPolicy: { SmartCategoryPolicy(isEnabled: true) }
        )

        let outcome = await processor.process(Self.rawCapture(text: "func paste() { return true }"))

        #expect(outcome == .refreshedIncrementally)
        #expect(repository.createdCategoryNames.isEmpty)
        #expect(repository.assignedCategoryNames.isEmpty)
    }

    @Test("inserted images store locally recognized text for unified search")
    func insertedImagesStoreRecognizedText() async {
        let item = Self.item(updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let repository = CaptureTestRepository(items: [])
        repository.nextUpsertResult = ClipboardUpsertResult(
            item: item,
            disposition: .inserted
        )
        let model = AppModel(repository: repository, pasteService: CaptureTestPasteService())
        let processor = ClipboardCaptureProcessor(
            normalizer: Self.normalizer,
            repository: repository,
            model: model,
            retentionPolicy: { RetentionPolicy(maxAge: nil, maxItemCount: 500, maxBytes: nil) },
            textRecognizer: CaptureTestTextRecognizer(text: "Invoice 2048")
        )

        let outcome = await processor.process(Self.rawImageCapture)

        #expect(outcome == .inserted)
        #expect(repository.recognizedText(for: item.id) == "Invoice 2048")
    }

    private static let normalizer = ClipboardNormalizer(
        maxRepresentationBytes: 1_000,
        maxCaptureBytes: 2_000
    )

    private static let rawCapture = rawCapture()

    private static let rawImageCapture = RawClipboardCapture(
        sourceAppName: "Preview",
        sourceBundleID: "com.apple.Preview",
        items: [
            RawClipboardItem(representations: [
                RawClipboardRepresentation(type: "public.png", data: Data([0x89, 0x50]))
            ])
        ]
    )

    private static func rawCapture(text: String = "Captured") -> RawClipboardCapture {
        RawClipboardCapture(
            sourceAppName: "Notes",
            sourceBundleID: "com.apple.Notes",
            items: [
                RawClipboardItem(representations: [
                    RawClipboardRepresentation(
                        type: "public.utf8-plain-text",
                        data: Data(text.utf8)
                    )
                ])
            ]
        )
    }

    private static func item(
        id: UUID = UUID(),
        updatedAt: Date,
        appName: String = "Notes",
        preview: String = "Captured"
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            createdAt: .distantPast,
            updatedAt: updatedAt,
            appName: appName,
            bundleID: "local.clipflow.tests",
            kind: .text,
            previewText: preview,
            searchText: preview.lowercased(),
            byteSize: preview.utf8.count,
            contentHash: "stable-hash-\(preview)",
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
    private var upserts = 0
    private var retentions = 0
    private var storedCategories: [ClipCategory] = []
    private var storedAssignments: [(UUID, UUID)] = []
    private var recognizedTexts: [UUID: String] = [:]
    var nextUpsertResult: ClipboardUpsertResult?

    init(items: [ClipboardItem]) {
        self.items = items
    }

    var searchCount: Int { lock.withLock { searches } }
    var upsertCount: Int { lock.withLock { upserts } }
    var retentionCount: Int { lock.withLock { retentions } }
    var createdCategoryNames: [String] { lock.withLock { storedCategories.map(\.name) } }
    var assignedCategoryNames: [String] {
        lock.withLock {
            storedAssignments.compactMap { assignment in
                storedCategories.first { $0.id == assignment.1 }?.name
            }
        }
    }
    func recognizedText(for itemID: UUID) -> String? {
        lock.withLock { recognizedTexts[itemID] }
    }

    func replaceItems(with items: [ClipboardItem]) {
        lock.withLock { self.items = items }
    }

    func search(_ query: SearchQuery, limit: Int, offset: Int) throws -> [ClipboardItem] {
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
            upserts += 1
            guard let nextUpsertResult else { throw CaptureTestError.missingResult }
            switch nextUpsertResult.disposition {
            case .inserted:
                items.insert(nextUpsertResult.item, at: 0)
            case .refreshed:
                if let index = items.firstIndex(where: {
                    $0.id == nextUpsertResult.item.id
                }) {
                    items[index] = nextUpsertResult.item
                }
            }
            return nextUpsertResult
        }
    }

    func applyRetention(_ policy: RetentionPolicy, now: Date) throws -> [UUID] {
        lock.withLock {
            retentions += 1
            return []
        }
    }

    func updateRecognizedText(_ text: String, for itemID: UUID) throws {
        lock.withLock { recognizedTexts[itemID] = text }
    }

    func markUsed(_ id: UUID) throws {}
    func setFavorite(_ favorite: Bool, for id: UUID) throws {}
    func rename(_ id: UUID, title: String?) throws {}
    func delete(_ id: UUID) throws {}
    func allCategories() throws -> [ClipCategory] {
        lock.withLock { storedCategories }
    }

    func createCategory(name: String) throws -> ClipCategory {
        lock.withLock {
            let category = ClipCategory(
                id: UUID(),
                name: name,
                createdAt: Date(),
                sortOrder: storedCategories.count
            )
            storedCategories.append(category)
            return category
        }
    }

    func assign(itemID: UUID, categoryID: UUID) throws {
        lock.withLock {
            storedAssignments.append((itemID, categoryID))
        }
    }

    func quickPasteSlots() throws -> [QuickPasteSlot] { [] }
    func setQuickPasteSlot(_ index: Int, itemID: UUID) throws {}
    func clearQuickPasteSlot(_ index: Int) throws {}
    func pasteStackItems() throws -> [PasteStackItem] { [] }
    func appendToPasteStack(itemID: UUID) throws {}
    func removePasteStackItem(at position: Int) throws {}
    func clearPasteStack() throws {}
    func setTemporaryPolicy(for itemID: UUID, expiresAt: Date?, isOneTime: Bool) throws {}
    func templates() throws -> [SnippetTemplate] { [] }
    func createTemplate(title: String, body: String) throws -> SnippetTemplate {
        SnippetTemplate(id: UUID(), title: title, body: body, createdAt: Date(), updatedAt: Date())
    }
    func deleteCategory(_ id: UUID) throws {}
}

private actor CaptureTestPasteService: PasteServing {
    func paste(item: ClipboardItem) async throws -> PasteOutcome { .pasted }
}

private actor CaptureTestTextRecognizer: LocalTextRecognizing {
    private let text: String?

    init(text: String?) {
        self.text = text
    }

    func recognizeText(in capture: NormalizedCapture) async throws -> String? {
        text
    }
}

private enum CaptureTestError: Error {
    case missingResult
    case unsupported
}
