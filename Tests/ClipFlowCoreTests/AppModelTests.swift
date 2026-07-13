import Foundation
import Testing
import ClipFlowCore
import ClipFlowSystem
@testable import ClipFlowUI

@Suite("Application model")
@MainActor
struct AppModelTests {
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

    private static func item(preview: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), createdAt: .distantPast, updatedAt: .distantPast,
            appName: "Notes", bundleID: "com.apple.Notes", kind: .text,
            previewText: preview, searchText: preview.lowercased(),
            byteSize: preview.utf8.count, contentHash: preview,
            isFavorite: false, lastUsedAt: nil, customTitle: nil,
            hasExternalPayload: false
        )
    }
}

private final class FakeHistoryRepository: HistoryRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let items: [ClipboardItem]
    private var used: [UUID] = []
    private var query: SearchQuery?
    private var favorites: [(UUID, Bool)] = []
    private var renames: [(UUID, String?)] = []
    private var deletions: [UUID] = []
    private var storedCategories: [ClipCategory] = []
    private var storedAssignments: [(UUID, UUID)] = []
    private var categoryDeletions: [UUID] = []

    init(items: [ClipboardItem]) { self.items = items }

    var markedUsed: [UUID] { lock.withLock { used } }
    var lastQuery: SearchQuery? { lock.withLock { query } }
    var favoriteChanges: [(UUID, Bool)] { lock.withLock { favorites } }
    var renameChanges: [(UUID, String?)] { lock.withLock { renames } }
    var deletedIDs: [UUID] { lock.withLock { deletions } }
    var assignments: [(UUID, UUID)] { lock.withLock { storedAssignments } }
    var deletedCategoryIDs: [UUID] { lock.withLock { categoryDeletions } }

    func search(_ query: SearchQuery) throws -> [ClipboardItem] {
        lock.withLock { self.query = query }
        return items.filter {
            query.score(ItemSearchDocument(
                id: $0.id, title: $0.displayTitle, body: $0.searchText,
                appName: $0.appName, isFavorite: $0.isFavorite, kind: $0.kind
            )) != nil
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
    private(set) var pastedIDs: [UUID] = []

    func paste(item: ClipboardItem) async throws -> PasteOutcome {
        pastedIDs.append(item.id)
        return .pasted
    }
}

@MainActor
private final class FakeItemIntegrationService: ItemIntegrationServing {
    private(set) var previewedIDs: [UUID] = []
    private(set) var performedActions: [(ApplicationAction, UUID)] = []

    func availableActions(for item: ClipboardItem) -> [ApplicationAction] {
        [.openFeishu]
    }

    func preview(_ item: ClipboardItem) throws {
        previewedIDs.append(item.id)
    }

    func dragProvider(for item: ClipboardItem) -> NSItemProvider? {
        nil
    }

    func perform(_ action: ApplicationAction, for item: ClipboardItem) async throws {
        performedActions.append((action, item.id))
    }
}
