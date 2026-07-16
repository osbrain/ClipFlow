import AppKit
import Foundation
import Testing
import ClipFlowCore
import ClipFlowSystem
@testable import ClipFlowUI

@Suite("Application model")
@MainActor
struct AppModelTests {
    @Test("paste destination is visible and can be cleared")
    func tracksPasteDestination() {
        let model = AppModel(
            repository: FakeHistoryRepository(items: []),
            pasteService: FakePasteService()
        )

        model.updatePasteDestination(name: "Notes")
        #expect(model.pasteDestinationName == "Notes")

        model.updatePasteDestination(name: nil)
        #expect(model.pasteDestinationName == nil)
    }

    @Test("search selects the first result and paste marks it used")
    func searchSelectsFirstResultAndPasteMarksUsage() async throws {
        let alpha = Self.item(preview: "Alpha")
        let beta = Self.item(preview: "Beta")
        let repository = FakeHistoryRepository(items: [alpha, beta])
        let pasteService = FakePasteService()
        let model = AppModel(repository: repository, pasteService: pasteService)

        model.searchText = "Beta"
        await model.reload()

        #expect(model.selectedItem?.id == beta.id)
        await model.pasteSelection()
        #expect(repository.markedUsed == [beta.id])
        #expect(await pasteService.pastedIDs == [beta.id])
    }

    @Test("passes sidebar filters to the repository query")
    func passesSidebarFiltersToRepository() async {
        let repository = FakeHistoryRepository(items: [])
        let model = AppModel(
            repository: repository,
            pasteService: FakePasteService()
        )
        let categoryID = UUID()

        model.selectedCategoryID = categoryID
        model.selectedKind = .image
        model.favoritesOnly = true
        await model.reload()

        #expect(repository.lastQuery?.categoryID == categoryID)
        #expect(repository.lastQuery?.kind == .image)
        #expect(repository.lastQuery?.favoritesOnly == true)
        #expect(repository.lastLimit == 500)
    }

    @Test("applying a history filter clears mutually exclusive repository values")
    func applyingHistoryFilterClearsOldValues() {
        let repository = FakeHistoryRepository(items: [])
        let model = AppModel(
            repository: repository,
            pasteService: FakePasteService()
        )
        let categoryID = UUID()

        model.selectedCategoryID = categoryID
        model.selectedKind = .image
        model.favoritesOnly = true

        model.apply(.kind(.file))
        #expect(model.selectedKind == .file)
        #expect(model.selectedCategoryID == nil)
        #expect(!model.favoritesOnly)

        model.apply(.category(categoryID))
        #expect(model.selectedKind == nil)
        #expect(model.selectedCategoryID == categoryID)
        #expect(!model.favoritesOnly)

        model.apply(.favorites)
        #expect(model.selectedKind == nil)
        #expect(model.selectedCategoryID == nil)
        #expect(model.favoritesOnly)
    }

    @Test("plain text paste uses an explicit mode and marks the item used")
    func plainTextPasteUsesExplicitMode() async {
        let item = Self.item(preview: "Plain")
        let repository = FakeHistoryRepository(items: [item])
        let pasteService = FakePasteService()
        let model = AppModel(repository: repository, pasteService: pasteService)
        await model.reload()

        await model.pasteSelectionAsPlainText()

        #expect(repository.markedUsed == [item.id])
        #expect(await pasteService.pasteRequests == [
            FakePasteRequest(itemID: item.id, mode: .plainText)
        ])
    }

    @Test("favorite rename and delete actions update the repository")
    func itemActionsUpdateRepository() async {
        let item = Self.item(preview: "Original")
        let repository = FakeHistoryRepository(items: [item])
        let model = AppModel(
            repository: repository,
            pasteService: FakePasteService()
        )
        await model.reload()

        await model.toggleFavoriteSelection()
        await model.renameSelection(to: "Renamed")
        await model.deleteSelection()

        #expect(repository.favoriteChanges.count == 1)
        #expect(repository.favoriteChanges.first?.0 == item.id)
        #expect(repository.favoriteChanges.first?.1 == true)
        #expect(repository.renameChanges.count == 1)
        #expect(repository.renameChanges.first?.0 == item.id)
        #expect(repository.renameChanges.first?.1 == "Renamed")
        #expect(repository.deletedIDs == [item.id])
    }

    @Test("creates assigns and deletes a custom category")
    func managesCustomCategory() async {
        let item = Self.item(preview: "Categorize")
        let repository = FakeHistoryRepository(items: [item])
        let model = AppModel(
            repository: repository,
            pasteService: FakePasteService()
        )
        await model.reload()

        await model.createCategory(named: "Work")
        let category = model.categories.first
        #expect(category?.name == "Work")
        await model.assignSelection(to: category!.id)
        await model.deleteCategory(category!.id)

        #expect(repository.assignments.count == 1)
        #expect(repository.assignments.first?.0 == item.id)
        #expect(repository.assignments.first?.1 == category?.id)
        #expect(repository.deletedCategoryIDs == [category!.id])
    }

    @Test("routes preview and optional application actions for the selection")
    func routesSelectionIntegrations() async {
        let item = Self.item(preview: "Send this")
        let repository = FakeHistoryRepository(items: [item])
        let integrations = FakeItemIntegrationService()
        let model = AppModel(
            repository: repository,
            pasteService: FakePasteService(),
            itemIntegrations: integrations
        )
        await model.reload()

        #expect(model.availableApplicationActions == [.openFeishu])
        model.previewSelection()
        await model.performApplicationAction(.openFeishu)

        #expect(integrations.previewedIDs == [item.id])
        #expect(integrations.performedActions.count == 1)
        #expect(integrations.performedActions.first?.0 == .openFeishu)
        #expect(integrations.performedActions.first?.1 == item.id)
    }

    @Test("routes content-specific actions and keeps failures visible")
    func routesContextActions() async {
        let item = Self.item(preview: "https://example.com", kind: .link)
        let repository = FakeHistoryRepository(items: [item])
        let integrations = FakeItemIntegrationService()
        integrations.contextActions = [.pasteOriginal, .openLink, .pastePlainText]
        let model = AppModel(
            repository: repository,
            pasteService: FakePasteService(),
            itemIntegrations: integrations
        )
        await model.reload()

        #expect(model.availableContextActions == [
            .pasteOriginal, .openLink, .pastePlainText
        ])
        await model.performContextAction(.openLink)
        #expect(integrations.performedContextActions == [
            PerformedContextAction(action: .openLink, itemID: item.id)
        ])

        integrations.shouldFailContextAction = true
        await model.performContextAction(.openLink)
        #expect(model.errorMessage == L10n.string("error.contextAction"))
        #expect(model.selectedItemID == item.id)
    }

    @Test("reload publishes metadata visuals without loading thumbnails")
    func reloadPublishesMetadataVisuals() async throws {
        let item = Self.item(preview: "Visual")
        let repository = FakeHistoryRepository(items: [item])
        let visualService = FakeClipboardVisualService()
        let model = AppModel(
            repository: repository,
            pasteService: FakePasteService(),
            visualService: visualService
        )

        await model.reload()

        let visual = try #require(model.visuals[item.id])
        #expect(visual.itemID == item.id)
        #expect(visual.kind == item.kind.presentation)
        #expect(visual.thumbnail == nil)
        #expect(visualService.metadataItemIDs == [item.id])
        #expect(visualService.requestedItems.isEmpty)
    }

    @Test("reload preserves a completed thumbnail for unchanged content")
    func reloadPreservesThumbnailForUnchangedContent() async throws {
        let item = Self.item(preview: "Stable")
        let repository = FakeHistoryRepository(items: [item])
        let visualService = FakeClipboardVisualService()
        let model = AppModel(
            repository: repository,
            pasteService: FakePasteService(),
            visualService: visualService
        )
        await model.reload()

        model.requestThumbnail(for: item, maximumPixelSize: 64)
        await visualService.waitForRequestCount(1)
        await visualService.completeRequest(at: 0, with: Self.image(width: 37))
        await model.reload()

        let thumbnail = try #require(model.visuals[item.id]?.thumbnail)
        #expect(thumbnail.size.width == 37)
        #expect(visualService.requestedItems.count == 1)
    }

    @Test("smaller thumbnail requests never downgrade a larger request")
    func smallerThumbnailRequestDoesNotDowngrade() async throws {
        let item = Self.item(preview: "Priority")
        let visualService = FakeClipboardVisualService()
        let model = AppModel(
            repository: FakeHistoryRepository(items: [item]),
            pasteService: FakePasteService(),
            visualService: visualService
        )
        await model.reload()

        model.requestThumbnail(for: item, maximumPixelSize: 720)
        await visualService.waitForRequestCount(1)
        model.requestThumbnail(for: item, maximumPixelSize: 320)

        #expect(visualService.requestedPixelSizes == [720])
        await visualService.completeRequest(at: 0, with: Self.image(width: 72))
        let thumbnail = try #require(model.visuals[item.id]?.thumbnail)
        #expect(thumbnail.size.width == 72)
    }

    @Test("larger thumbnail requests supersede smaller in-flight work")
    func largerThumbnailRequestUpgrades() async throws {
        let item = Self.item(preview: "Upgrade")
        let visualService = FakeClipboardVisualService()
        let model = AppModel(
            repository: FakeHistoryRepository(items: [item]),
            pasteService: FakePasteService(),
            visualService: visualService
        )
        await model.reload()

        model.requestThumbnail(for: item, maximumPixelSize: 320)
        await visualService.waitForRequestCount(1)
        model.requestThumbnail(for: item, maximumPixelSize: 720)
        await visualService.waitForRequestCount(2)

        #expect(visualService.requestedPixelSizes == [320, 720])
        await visualService.completeRequest(at: 0, with: Self.image(width: 32))
        #expect(model.visuals[item.id]?.thumbnail == nil)
        await visualService.completeRequest(at: 1, with: Self.image(width: 72))
        let thumbnail = try #require(model.visuals[item.id]?.thumbnail)
        #expect(thumbnail.size.width == 72)
    }

    @Test("removed items discard thumbnails that finish after reload")
    func removedItemsDiscardLateThumbnails() async {
        let item = Self.item(preview: "Remove")
        let repository = FakeHistoryRepository(items: [item])
        let visualService = FakeClipboardVisualService()
        let model = AppModel(
            repository: repository,
            pasteService: FakePasteService(),
            visualService: visualService
        )
        await model.reload()

        model.requestThumbnail(for: item, maximumPixelSize: 64)
        await visualService.waitForRequestCount(1)
        repository.replaceItems(with: [])
        await model.reload()
        await visualService.completeRequest(at: 0, with: Self.image(width: 11))

        #expect(model.visuals[item.id] == nil)
    }

    @Test("replaced content discards its old thumbnail and accepts the current result")
    func replacedContentMatchesThumbnailByIdentityAndHash() async throws {
        let itemID = UUID()
        let original = Self.item(id: itemID, preview: "Original")
        let replacement = Self.item(id: itemID, preview: "Replacement")
        let repository = FakeHistoryRepository(items: [original])
        let visualService = FakeClipboardVisualService()
        let model = AppModel(
            repository: repository,
            pasteService: FakePasteService(),
            visualService: visualService
        )
        await model.reload()

        model.requestThumbnail(for: original, maximumPixelSize: 64)
        await visualService.waitForRequestCount(1)
        repository.replaceItems(with: [replacement])
        await model.reload()
        #expect(model.visuals[itemID]?.thumbnail == nil)
        await visualService.completeRequest(at: 0, with: Self.image(width: 13))
        #expect(model.visuals[itemID]?.thumbnail == nil)

        model.requestThumbnail(for: replacement, maximumPixelSize: 64)
        await visualService.waitForRequestCount(2)
        await visualService.completeRequest(at: 1, with: Self.image(width: 29))

        let thumbnail = try #require(model.visuals[itemID]?.thumbnail)
        #expect(thumbnail.size.width == 29)
    }

    @Test("duplicate capture refreshes and reorders without repository reload")
    func duplicateCaptureRefreshesIncrementally() async {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let duplicateID = UUID()
        let other = Self.item(preview: "Other", updatedAt: base.addingTimeInterval(60))
        let duplicate = Self.item(
            id: duplicateID,
            preview: "Duplicate",
            updatedAt: base
        )
        let repository = FakeHistoryRepository(items: [other, duplicate])
        let visualService = FakeClipboardVisualService()
        let model = AppModel(
            repository: repository,
            pasteService: FakePasteService(),
            visualService: visualService
        )
        await model.reload()
        let refreshed = Self.item(
            id: duplicateID,
            preview: "Duplicate",
            updatedAt: base.addingTimeInterval(120),
            appName: "Safari",
            bundleID: "com.apple.Safari"
        )

        let refreshedInPlace = model.refreshCapturedItem(refreshed)

        #expect(refreshedInPlace)
        #expect(model.items.map(\.id) == [duplicateID, other.id])
        #expect(model.items.first?.appName == "Safari")
        #expect(repository.searchCount == 1)
    }

    @Test("filtered history declines an incremental capture refresh")
    func filteredHistoryDeclinesIncrementalRefresh() async {
        let item = Self.item(preview: "Filtered")
        let repository = FakeHistoryRepository(items: [item])
        let model = AppModel(repository: repository, pasteService: FakePasteService())
        model.searchText = "Filtered"
        await model.reload()

        #expect(!model.refreshCapturedItem(item))
        #expect(repository.searchCount == 1)
    }

    private static func item(
        id: UUID = UUID(),
        preview: String,
        kind: ClipboardKind = .text,
        updatedAt: Date = .distantPast,
        appName: String = "Notes",
        bundleID: String? = "com.apple.Notes"
    ) -> ClipboardItem {
        ClipboardItem(
            id: id, createdAt: .distantPast, updatedAt: updatedAt,
            appName: appName, bundleID: bundleID, kind: kind,
            previewText: preview, searchText: preview.lowercased(),
            byteSize: preview.utf8.count, contentHash: preview,
            isFavorite: false, lastUsedAt: nil, customTitle: nil,
            hasExternalPayload: false
        )
    }

    private static func image(width: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: width, height: 1))
    }
}

private final class FakeHistoryRepository: HistoryRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ClipboardItem]
    private var used: [UUID] = []
    private var query: SearchQuery?
    private var limit: Int?
    private var searches = 0
    private var favorites: [(UUID, Bool)] = []
    private var renames: [(UUID, String?)] = []
    private var deletions: [UUID] = []
    private var storedCategories: [ClipCategory] = []
    private var storedAssignments: [(UUID, UUID)] = []
    private var categoryDeletions: [UUID] = []

    init(items: [ClipboardItem]) { self.items = items }

    var markedUsed: [UUID] { lock.withLock { used } }
    var lastQuery: SearchQuery? { lock.withLock { query } }
    var lastLimit: Int? { lock.withLock { limit } }
    var searchCount: Int { lock.withLock { searches } }
    var favoriteChanges: [(UUID, Bool)] { lock.withLock { favorites } }
    var renameChanges: [(UUID, String?)] { lock.withLock { renames } }
    var deletedIDs: [UUID] { lock.withLock { deletions } }
    var assignments: [(UUID, UUID)] { lock.withLock { storedAssignments } }
    var deletedCategoryIDs: [UUID] { lock.withLock { categoryDeletions } }

    func replaceItems(with items: [ClipboardItem]) {
        lock.withLock { self.items = items }
    }

    func search(_ query: SearchQuery, limit: Int) throws -> [ClipboardItem] {
        lock.withLock {
            self.query = query
            self.limit = limit
            searches += 1
        }
        return lock.withLock {
            items.filter {
                query.score(ItemSearchDocument(
                    id: $0.id, title: $0.displayTitle, body: $0.searchText,
                    appName: $0.appName, isFavorite: $0.isFavorite, kind: $0.kind
                )) != nil
            }.prefix(limit).map { $0 }
        }
    }

    func markUsed(_ id: UUID) throws {
        lock.withLock { used.append(id) }
    }

    func setFavorite(_ favorite: Bool, for id: UUID) throws {
        lock.withLock { favorites.append((id, favorite)) }
    }

    func rename(_ id: UUID, title: String?) throws {
        lock.withLock { renames.append((id, title)) }
    }

    func delete(_ id: UUID) throws {
        lock.withLock { deletions.append(id) }
    }

    func allCategories() throws -> [ClipCategory] {
        lock.withLock { storedCategories }
    }

    func createCategory(name: String) throws -> ClipCategory {
        lock.withLock {
            let category = ClipCategory(
                id: UUID(), name: name, createdAt: Date(),
                sortOrder: storedCategories.count
            )
            storedCategories.append(category)
            return category
        }
    }

    func assign(itemID: UUID, categoryID: UUID) throws {
        lock.withLock { storedAssignments.append((itemID, categoryID)) }
    }

    func deleteCategory(_ id: UUID) throws {
        lock.withLock {
            categoryDeletions.append(id)
            storedCategories.removeAll { $0.id == id }
        }
    }
}

private actor FakePasteService: PasteServing {
    private(set) var pasteRequests: [FakePasteRequest] = []

    var pastedIDs: [UUID] {
        pasteRequests.map(\.itemID)
    }

    func paste(item: ClipboardItem) async throws -> PasteOutcome {
        pasteRequests.append(FakePasteRequest(itemID: item.id, mode: nil))
        return .pasted
    }

    func paste(item: ClipboardItem, mode: PasteMode) async throws -> PasteOutcome {
        pasteRequests.append(FakePasteRequest(itemID: item.id, mode: mode))
        return .pasted
    }
}

private struct FakePasteRequest: Equatable, Sendable {
    let itemID: UUID
    let mode: PasteMode?
}

@MainActor
private final class FakeItemIntegrationService: ItemIntegrationServing {
    private(set) var previewedIDs: [UUID] = []
    private(set) var performedActions: [(ApplicationAction, UUID)] = []
    var contextActions: [ItemContextAction] = []
    var shouldFailContextAction = false
    private(set) var performedContextActions: [PerformedContextAction] = []

    func availableActions(for item: ClipboardItem) -> [ApplicationAction] {
        [.openFeishu]
    }

    func preview(_ item: ClipboardItem) throws {
        previewedIDs.append(item.id)
    }

    func availableContextActions(for item: ClipboardItem) -> [ItemContextAction] {
        contextActions
    }

    func dragProvider(for item: ClipboardItem) -> NSItemProvider? {
        nil
    }

    func perform(_ action: ApplicationAction, for item: ClipboardItem) async throws {
        performedActions.append((action, item.id))
    }

    func perform(_ action: ItemContextAction, for item: ClipboardItem) throws {
        if shouldFailContextAction {
            throw FakeContextActionError.failed
        }
        performedContextActions.append(
            PerformedContextAction(action: action, itemID: item.id)
        )
    }
}

private struct PerformedContextAction: Equatable {
    let action: ItemContextAction
    let itemID: UUID
}

private enum FakeContextActionError: Error {
    case failed
}

@MainActor
private final class FakeClipboardVisualService: ClipboardVisualServing {
    private struct PendingRequest {
        let continuation: CheckedContinuation<NSImage?, Never>
    }

    private(set) var metadataItemIDs: [UUID] = []
    private(set) var requestedItems: [ClipboardItem] = []
    private(set) var requestedPixelSizes: [Int] = []
    private var pendingRequests: [Int: PendingRequest] = [:]

    func metadataVisual(for item: ClipboardItem) -> ClipboardVisualDescriptor {
        metadataItemIDs.append(item.id)
        return ClipboardVisualDescriptor(
            itemID: item.id,
            applicationIcon: nil,
            thumbnail: nil,
            kind: item.kind.presentation
        )
    }

    func loadThumbnail(for item: ClipboardItem, maximumPixelSize: Int) async -> NSImage? {
        let index = requestedItems.count
        requestedItems.append(item)
        requestedPixelSizes.append(maximumPixelSize)
        return await withCheckedContinuation { continuation in
            pendingRequests[index] = PendingRequest(continuation: continuation)
        }
    }

    func waitForRequestCount(_ expectedCount: Int) async {
        while requestedItems.count < expectedCount {
            await Task.yield()
        }
    }

    func completeRequest(at index: Int, with image: NSImage?) async {
        pendingRequests.removeValue(forKey: index)?.continuation.resume(returning: image)
        await Task.yield()
    }
}
