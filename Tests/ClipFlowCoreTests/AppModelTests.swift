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
        #expect(repository.lastLimit == 151)
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

    @Test("one-time clips are deleted only after a successful paste")
    func oneTimeClipDeletesAfterPaste() async {
        let item = Self.item(preview: "One-time", isOneTime: true)
        let repository = FakeHistoryRepository(items: [item])
        let pasteService = FakePasteService()
        let model = AppModel(repository: repository, pasteService: pasteService)
        await model.reload()

        await model.pasteSelection()

        #expect(await pasteService.pastedIDs == [item.id])
        #expect(repository.deletedIDs == [item.id])
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

    @Test("targeted item actions keep their original item even if selection changes")
    func targetedItemActionsIgnoreSelectionDrift() async {
        let first = Self.item(preview: "First")
        let second = Self.item(preview: "Second")
        let repository = FakeHistoryRepository(items: [first, second])
        let model = AppModel(
            repository: repository,
            pasteService: FakePasteService()
        )
        await model.reload()

        model.selectedItemID = first.id
        model.selectedItemID = second.id
        await model.renameItem(first.id, to: "Pinned rename")
        await model.deleteItem(first.id)

        #expect(repository.renameChanges.count == 1)
        #expect(repository.renameChanges.first?.0 == first.id)
        #expect(repository.renameChanges.first?.1 == "Pinned rename")
        #expect(repository.deletedIDs == [first.id])
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

    @Test("quick paste slots load assign clear and paste by slot")
    func quickPasteSlotsLoadAssignClearAndPaste() async {
        let first = Self.item(preview: "First")
        let second = Self.item(preview: "Second")
        let repository = FakeHistoryRepository(items: [first, second])
        let pasteService = FakePasteService()
        let model = AppModel(repository: repository, pasteService: pasteService)

        await model.reload()
        await model.setQuickPasteSlot(1, itemID: first.id)
        await model.setQuickPasteSlot(1, itemID: second.id)

        #expect(model.quickPasteSlots.map(\.index) == [1])
        #expect(model.quickPasteSlots.first?.item.id == second.id)

        await model.pasteQuickSlot(1)
        #expect(await pasteService.pastedIDs == [second.id])
        #expect(repository.markedUsed == [second.id])

        await model.clearQuickPasteSlot(1)
        #expect(model.quickPasteSlots.isEmpty)
    }

    @Test("paste stack adds selected history and pastes the next item in order")
    func pasteStackAddsAndPastesInOrder() async {
        let first = Self.item(preview: "First")
        let second = Self.item(preview: "Second")
        let repository = FakeHistoryRepository(items: [first, second])
        let pasteService = FakePasteService()
        let model = AppModel(repository: repository, pasteService: pasteService)

        await model.reload()
        await model.addToPasteStack(first.id)
        await model.addToPasteStack(second.id)

        #expect(model.pasteStack.map(\.item.id) == [first.id, second.id])

        await model.pasteNextStackItem()

        #expect(await pasteService.pastedIDs == [first.id])
        #expect(model.pasteStack.map(\.item.id) == [second.id])
        #expect(repository.markedUsed == [first.id])
    }

    @Test("main panel exposes quick paste strip and command shortcuts")
    func mainPanelExposesQuickPasteStrip() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ClipFlowUI/MainPanelView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("QuickPasteSlotStrip"))
        #expect(!source.contains(".keyboardShortcut(shortcut(for: index), modifiers: [.command, .option])"))
        #expect(source.contains("quickPaste.pinToSlot"))
        #expect(source.contains("pinSelectionToSlot"))
        #expect(source.contains("quickPaste.add"))
        #expect(source.contains("quickPaste.emptyDescription"))
        #expect(source.contains("QuickPasteEmptyStateIcon"))
        #expect(source.contains("quickPaste.shortcutHint"))
        #expect(!source.contains("ClipFlowMiniEmptyStateIllustration(symbol: \"pin\")"))
        #expect(source.contains("ForEach(slots)"))
        #expect(!source.contains("slot?.item.displayTitle ?? L10n.string(\"quickPaste.empty\")"))
    }

    @Test("main panel exposes a compact sequential paste stack")
    func mainPanelExposesPasteStack() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ClipFlowUI/MainPanelView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("PasteStackStrip"))
        #expect(source.contains("pasteStack.add"))
        #expect(source.contains("pasteNextStackItem"))
        #expect(source.contains("pasteStack.clear"))
    }

    @Test("main panel groups copy and transform actions under content operations")
    func mainPanelGroupsContentOperations() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ClipFlowUI/MainPanelView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("contextAction.contentOperations"))
        #expect(source.contains("isContentOperation"))
    }

    @Test("history context menu uses icon labels for primary actions")
    func historyContextMenuUsesIconLabels() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ClipFlowUI/MainPanelView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("Label(L10n.string(\"detail.paste\"), systemImage: \"clipboard\")"))
        #expect(source.contains("Label(L10n.string(\"detail.preview\"), systemImage: \"eye\")"))
        #expect(source.contains("Label(L10n.string(\"action.rename\"), systemImage: \"pencil\")"))
        #expect(source.contains("Label(L10n.string(\"action.delete\"), systemImage: \"trash\")"))
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

    @Test("routes content copy actions through integrations without pasting")
    func routesContentCopyActionsThroughIntegrations() async {
        let item = Self.item(preview: "Copy me")
        let repository = FakeHistoryRepository(items: [item])
        let pasteService = FakePasteService()
        let integrations = FakeItemIntegrationService()
        integrations.contextActions = [.copyOriginal, .copyPlainText, .copyCleanText]
        let model = AppModel(
            repository: repository,
            pasteService: pasteService,
            itemIntegrations: integrations
        )
        await model.reload()

        await model.performContextAction(.copyCleanText)

        #expect(integrations.performedContextActions == [
            PerformedContextAction(action: .copyCleanText, itemID: item.id)
        ])
        #expect(await pasteService.pasteRequests.isEmpty)
        #expect(repository.markedUsed.isEmpty)
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
        bundleID: String? = "com.apple.Notes",
        isOneTime: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            id: id, createdAt: .distantPast, updatedAt: updatedAt,
            appName: appName, bundleID: bundleID, kind: kind,
            previewText: preview, searchText: preview.lowercased(),
            byteSize: preview.utf8.count, contentHash: preview,
            isFavorite: false, lastUsedAt: nil, customTitle: nil,
            hasExternalPayload: false,
            isOneTime: isOneTime
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
    private var storedQuickSlots: [Int: UUID] = [:]
    private var storedPasteStack: [(position: Int, itemID: UUID)] = []

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

    func search(_ query: SearchQuery, limit: Int, offset: Int) throws -> [ClipboardItem] {
        lock.withLock {
            self.query = query
            self.limit = limit
            searches += 1
        }
        return lock.withLock {
            items.filter {
                query.score(ItemSearchDocument(
                    id: $0.id, title: $0.displayTitle, body: $0.searchableText,
                    appName: $0.appName, isFavorite: $0.isFavorite, kind: $0.kind
                )) != nil
            }.dropFirst(offset).prefix(limit).map { $0 }
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

    func quickPasteSlots() throws -> [QuickPasteSlot] {
        lock.withLock {
            storedQuickSlots
                .sorted { $0.key < $1.key }
                .compactMap { index, itemID in
                    items.first { $0.id == itemID }.map {
                        QuickPasteSlot(index: index, item: $0)
                    }
                }
        }
    }

    func setQuickPasteSlot(_ index: Int, itemID: UUID) throws {
        lock.withLock {
            storedQuickSlots[index] = itemID
        }
    }

    func clearQuickPasteSlot(_ index: Int) throws {
        lock.withLock {
            storedQuickSlots[index] = nil
        }
    }

    func pasteStackItems() throws -> [PasteStackItem] {
        lock.withLock {
            storedPasteStack.compactMap { entry in
                items.first { $0.id == entry.itemID }.map {
                    PasteStackItem(position: entry.position, item: $0)
                }
            }
        }
    }

    func appendToPasteStack(itemID: UUID) throws {
        lock.withLock {
            let nextPosition = (storedPasteStack.last?.position ?? 0) + 1
            storedPasteStack.append((position: nextPosition, itemID: itemID))
        }
    }

    func removePasteStackItem(at position: Int) throws {
        lock.withLock {
            storedPasteStack.removeAll { $0.position == position }
        }
    }

    func clearPasteStack() throws {
        lock.withLock {
            storedPasteStack.removeAll()
        }
    }

    func setTemporaryPolicy(for itemID: UUID, expiresAt: Date?, isOneTime: Bool) throws {}
    func templates() throws -> [SnippetTemplate] { [] }
    func createTemplate(title: String, body: String) throws -> SnippetTemplate {
        SnippetTemplate(id: UUID(), title: title, body: body, createdAt: Date(), updatedAt: Date())
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
