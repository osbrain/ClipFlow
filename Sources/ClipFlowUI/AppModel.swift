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
public protocol ItemIntegrationServing: AnyObject {
    func availableActions(for item: ClipboardItem) -> [ApplicationAction]
    func preview(_ item: ClipboardItem) throws
    func dragProvider(for item: ClipboardItem) -> NSItemProvider?
    func perform(_ action: ApplicationAction, for item: ClipboardItem) async throws
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
    public private(set) var visuals: [UUID: ClipboardVisualDescriptor] = [:]

    @ObservationIgnored private let repository: any HistoryRepository
    @ObservationIgnored private let pasteService: any PasteServing
    @ObservationIgnored private let itemIntegrations: (any ItemIntegrationServing)?
    @ObservationIgnored private let visualService: (any ClipboardVisualServing)?
    @ObservationIgnored private var thumbnailTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var thumbnailRequestIDs: [UUID: UUID] = [:]

    public init(
        repository: any HistoryRepository,
        pasteService: any PasteServing,
        itemIntegrations: (any ItemIntegrationServing)? = nil,
        visualService: (any ClipboardVisualServing)? = nil
    ) {
        self.repository = repository
        self.pasteService = pasteService
        self.itemIntegrations = itemIntegrations
        self.visualService = visualService
    }

    public var selectedItem: ClipboardItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    public var availableApplicationActions: [ApplicationAction] {
        guard let selectedItem, let itemIntegrations else { return [] }
        return itemIntegrations.availableActions(for: selectedItem)
    }

    public func applicationActions(for item: ClipboardItem) -> [ApplicationAction] {
        itemIntegrations?.availableActions(for: item) ?? []
    }

    public func previewSelection() {
        guard let selectedItem, let itemIntegrations else { return }
        do {
            try itemIntegrations.preview(selectedItem)
            errorMessage = nil
        } catch {
            errorMessage = "Unable to preview the selected item: \(error.localizedDescription)"
        }
    }

    public func dragProvider(for item: ClipboardItem) -> NSItemProvider? {
        itemIntegrations?.dragProvider(for: item)
    }

    public func performApplicationAction(_ action: ApplicationAction) async {
        guard let selectedItem, let itemIntegrations else { return }
        do {
            try await itemIntegrations.perform(action, for: selectedItem)
            errorMessage = nil
        } catch {
            errorMessage = "Unable to complete \(action.displayName): \(error.localizedDescription)"
        }
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
            thumbnailTasks.values.forEach { $0.cancel() }
            thumbnailTasks.removeAll()
            thumbnailRequestIDs.removeAll()
            if let visualService {
                visuals = Dictionary(uniqueKeysWithValues: results.map {
                    ($0.id, visualService.metadataVisual(for: $0))
                })
            } else {
                visuals.removeAll()
            }
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

    public func requestThumbnail(for item: ClipboardItem, maximumPixelSize: Int) {
        guard maximumPixelSize > 0,
              let visualService,
              visuals[item.id] != nil,
              items.contains(where: {
                  $0.id == item.id && $0.contentHash == item.contentHash
              }) else {
            return
        }

        thumbnailTasks[item.id]?.cancel()
        let requestID = UUID()
        thumbnailRequestIDs[item.id] = requestID
        thumbnailTasks[item.id] = Task { @MainActor [weak self] in
            let thumbnail = await visualService.loadThumbnail(
                for: item,
                maximumPixelSize: maximumPixelSize
            )
            guard let self else { return }
            defer {
                if self.thumbnailRequestIDs[item.id] == requestID {
                    self.thumbnailTasks[item.id] = nil
                    self.thumbnailRequestIDs[item.id] = nil
                }
            }
            guard !Task.isCancelled,
                  self.thumbnailRequestIDs[item.id] == requestID,
                  self.items.contains(where: {
                      $0.id == item.id && $0.contentHash == item.contentHash
                  }),
                  let descriptor = self.visuals[item.id] else {
                return
            }
            self.visuals[item.id] = descriptor.replacingThumbnail(thumbnail)
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
