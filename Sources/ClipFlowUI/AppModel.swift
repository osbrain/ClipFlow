import ClipFlowCore
import ClipFlowStorage
import ClipFlowSystem
import Foundation
import Observation

public protocol HistoryRepository: Sendable {
    func search(_ query: SearchQuery) throws -> [ClipboardItem]
    func markUsed(_ id: UUID) throws
    func setFavorite(_ favorite: Bool, for id: UUID) throws
    func rename(_ id: UUID, title: String?) throws
    func delete(_ id: UUID) throws
    func allCategories() throws -> [ClipCategory]
    func createCategory(name: String) throws -> ClipCategory
    func assign(itemID: UUID, categoryID: UUID) throws
    func deleteCategory(_ id: UUID) throws
}

extension ClipboardRepository: HistoryRepository {}

public protocol PasteServing: Sendable {
    func paste(item: ClipboardItem) async throws -> PasteOutcome
}

@MainActor
@Observable
public final class AppModel {
    public var searchText = ""
    public var selectedCategoryID: UUID?
    public var selectedKind: ClipboardKind?
    public var favoritesOnly = false
    public private(set) var items: [ClipboardItem] = []
    public private(set) var categories: [ClipCategory] = []
    public var selectedItemID: UUID?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var lastPasteOutcome: PasteOutcome?

    @ObservationIgnored private let repository: any HistoryRepository
    @ObservationIgnored private let pasteService: any PasteServing

    public init(repository: any HistoryRepository, pasteService: any PasteServing) {
        self.repository = repository
        self.pasteService = pasteService
    }

    public var selectedItem: ClipboardItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    public func reload() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let query = SearchQuery(
                text: searchText,
                categoryID: selectedCategoryID,
                kind: selectedKind,
                favoritesOnly: favoritesOnly
            )
            let results = try repository.search(query)
            categories = try repository.allCategories()
            items = results
            if let selectedItemID, results.contains(where: { $0.id == selectedItemID }) {
                self.selectedItemID = selectedItemID
            } else {
                selectedItemID = results.first?.id
            }
            errorMessage = nil
        } catch {
            errorMessage = "Unable to load clipboard history: \(error.localizedDescription)"
        }
    }

    public func pasteSelection() async {
        guard let item = selectedItem else { return }

        do {
            lastPasteOutcome = try await pasteService.paste(item: item)
            try repository.markUsed(item.id)
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = "Unable to paste the selected item: \(error.localizedDescription)"
        }
    }

    public func toggleFavoriteSelection() async {
        guard let item = selectedItem else { return }
        do {
            try repository.setFavorite(!item.isFavorite, for: item.id)
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = "Unable to update favorite: \(error.localizedDescription)"
        }
    }

    public func renameSelection(to title: String?) async {
        guard let item = selectedItem else { return }
        do {
            try repository.rename(item.id, title: title)
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = "Unable to rename the selected item: \(error.localizedDescription)"
        }
    }

    public func deleteSelection() async {
        guard let item = selectedItem else { return }
        do {
            try repository.delete(item.id)
            errorMessage = nil
            selectedItemID = nil
            await reload()
        } catch {
            errorMessage = "Unable to delete the selected item: \(error.localizedDescription)"
        }
    }

    public func createCategory(named name: String) async {
        do {
            _ = try repository.createCategory(name: name)
            categories = try repository.allCategories()
            errorMessage = nil
        } catch {
            errorMessage = "Unable to create category: \(error.localizedDescription)"
        }
    }

    public func assignSelection(to categoryID: UUID) async {
        guard let item = selectedItem else { return }
        do {
            try repository.assign(itemID: item.id, categoryID: categoryID)
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = "Unable to assign category: \(error.localizedDescription)"
        }
    }

    public func deleteCategory(_ id: UUID) async {
        do {
            try repository.deleteCategory(id)
            if selectedCategoryID == id {
                selectedCategoryID = nil
            }
            categories = try repository.allCategories()
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = "Unable to delete category: \(error.localizedDescription)"
        }
    }

    public func selectPrevious() {
        moveSelection(by: -1)
    }

    public func selectNext() {
        moveSelection(by: 1)
    }

    private func moveSelection(by offset: Int) {
        guard !items.isEmpty else {
            selectedItemID = nil
            return
        }
        let currentIndex = selectedItemID.flatMap { id in
            items.firstIndex { $0.id == id }
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), items.count - 1)
        selectedItemID = items[nextIndex].id
    }
}
