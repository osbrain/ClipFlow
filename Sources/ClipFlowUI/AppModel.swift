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
    func paste(item: ClipboardItem, mode: PasteMode) async throws -> PasteOutcome
}

public extension PasteServing {
    func paste(item: ClipboardItem, mode: PasteMode) async throws -> PasteOutcome {
        try await paste(item: item)
    }
}

@MainActor
public protocol ItemIntegrationServing: AnyObject {
    func availableActions(for item: ClipboardItem) -> [ApplicationAction]
    func availableContextActions(for item: ClipboardItem) -> [ItemContextAction]
    func preview(_ item: ClipboardItem) throws
    func dragProvider(for item: ClipboardItem) -> NSItemProvider?
    func perform(_ action: ApplicationAction, for item: ClipboardItem) async throws
    func perform(_ action: ItemContextAction, for item: ClipboardItem) throws
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
    public private(set) var pasteDestinationName: String?

    @ObservationIgnored private let repository: any HistoryRepository
    @ObservationIgnored private let pasteService: any PasteServing
    @ObservationIgnored private let itemIntegrations: (any ItemIntegrationServing)?
    @ObservationIgnored private let visualService: (any ClipboardVisualServing)?
    @ObservationIgnored private var thumbnailTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var thumbnailRequestIDs: [UUID: UUID] = [:]
    @ObservationIgnored private var thumbnailPixelSizes: [UUID: Int] = [:]

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

    public func updatePasteDestination(name: String?) {
        pasteDestinationName = name
    }

    public func apply(_ filter: HistoryFilter) {
        let state = filter.repositoryState
        selectedKind = state.kind
        selectedCategoryID = state.categoryID
        favoritesOnly = state.favoritesOnly
    }

    public var availableApplicationActions: [ApplicationAction] {
        guard let selectedItem, let itemIntegrations else { return [] }
        return itemIntegrations.availableActions(for: selectedItem)
    }

    public var availableContextActions: [ItemContextAction] {
        guard let selectedItem else { return [] }
        return itemIntegrations?.availableContextActions(for: selectedItem)
            ?? ItemContextAction.available(for: selectedItem.kind)
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
            errorMessage = L10n.string("error.preview")
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
            errorMessage = L10n.format("error.action", action.localizedDisplayName)
        }
    }

    public func performContextAction(_ action: ItemContextAction) async {
        switch action {
        case .pasteOriginal:
            await pasteSelection()
        case .pastePlainText, .pasteFilePath:
            await pasteSelectionAsPlainText()
        case .quickLook:
            previewSelection()
        case .openLink, .openFile, .revealInFinder:
            guard let selectedItem, let itemIntegrations else {
                errorMessage = L10n.string("error.contextAction")
                return
            }
            do {
                try itemIntegrations.perform(action, for: selectedItem)
                errorMessage = nil
            } catch {
                errorMessage = L10n.string("error.contextAction")
            }
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
            let previousItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            let previousVisuals = visuals
            let unchangedItemIDs = Set<UUID>(results.compactMap { item in
                guard previousItems[item.id]?.contentHash == item.contentHash else {
                    return nil
                }
                return item.id
            })

            let obsoleteThumbnailIDs = thumbnailTasks.keys.filter {
                !unchangedItemIDs.contains($0)
            }
            for itemID in obsoleteThumbnailIDs {
                thumbnailTasks[itemID]?.cancel()
                thumbnailTasks[itemID] = nil
                thumbnailRequestIDs[itemID] = nil
            }
            thumbnailPixelSizes = thumbnailPixelSizes.filter {
                unchangedItemIDs.contains($0.key)
            }
            items = results
            if let visualService {
                visuals = Dictionary(uniqueKeysWithValues: results.map {
                    var descriptor = visualService.metadataVisual(for: $0)
                    if unchangedItemIDs.contains($0.id),
                       let thumbnail = previousVisuals[$0.id]?.thumbnail {
                        descriptor = descriptor.replacingThumbnail(thumbnail)
                    }
                    return ($0.id, descriptor)
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
            errorMessage = L10n.string("error.history.load")
        }
    }

    public func requestThumbnail(for item: ClipboardItem, maximumPixelSize: Int) {
        guard maximumPixelSize > 0,
              let visualService,
              visuals[item.id] != nil,
              items.contains(where: {
                  $0.id == item.id && $0.contentHash == item.contentHash
              }),
              maximumPixelSize > thumbnailPixelSizes[item.id, default: 0] else {
            return
        }

        thumbnailTasks[item.id]?.cancel()
        let requestID = UUID()
        thumbnailPixelSizes[item.id] = maximumPixelSize
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
            errorMessage = L10n.string("error.paste")
        }
    }

    public func pasteSelectionAsPlainText() async {
        guard let item = selectedItem else { return }

        do {
            lastPasteOutcome = try await pasteService.paste(item: item, mode: .plainText)
            try repository.markUsed(item.id)
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = L10n.string("error.paste")
        }
    }

    public func toggleFavoriteSelection() async {
        guard let item = selectedItem else { return }
        do {
            try repository.setFavorite(!item.isFavorite, for: item.id)
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = L10n.string("error.favorite")
        }
    }

    public func renameSelection(to title: String?) async {
        guard let item = selectedItem else { return }
        do {
            try repository.rename(item.id, title: title)
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = L10n.string("error.rename")
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
            errorMessage = L10n.string("error.delete")
        }
    }

    public func createCategory(named name: String) async {
        do {
            _ = try repository.createCategory(name: name)
            categories = try repository.allCategories()
            errorMessage = nil
        } catch {
            errorMessage = L10n.string("error.category.create")
        }
    }

    public func assignSelection(to categoryID: UUID) async {
        guard let item = selectedItem else { return }
        do {
            try repository.assign(itemID: item.id, categoryID: categoryID)
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = L10n.string("error.category.assign")
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
            errorMessage = L10n.string("error.category.delete")
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
