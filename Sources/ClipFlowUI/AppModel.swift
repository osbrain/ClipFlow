import ClipFlowCore
import ClipFlowStorage
import ClipFlowSystem
import Foundation
import Observation

public protocol HistoryRepository: Sendable {
    func search(_ query: SearchQuery, limit: Int, offset: Int) throws -> [ClipboardItem]
    func markUsed(_ id: UUID) throws
    func setFavorite(_ favorite: Bool, for id: UUID) throws
    func rename(_ id: UUID, title: String?) throws
    func delete(_ id: UUID) throws
    func allCategories() throws -> [ClipCategory]
    func createCategory(name: String) throws -> ClipCategory
    func assign(itemID: UUID, categoryID: UUID) throws
    func deleteCategory(_ id: UUID) throws
    func quickPasteSlots() throws -> [QuickPasteSlot]
    func setQuickPasteSlot(_ index: Int, itemID: UUID) throws
    func clearQuickPasteSlot(_ index: Int) throws
    func pasteStackItems() throws -> [PasteStackItem]
    func appendToPasteStack(itemID: UUID) throws
    func removePasteStackItem(at position: Int) throws
    func clearPasteStack() throws
    func setTemporaryPolicy(for itemID: UUID, expiresAt: Date?, isOneTime: Bool) throws
    func templates() throws -> [SnippetTemplate]
    func createTemplate(title: String, body: String) throws -> SnippetTemplate
}

public extension HistoryRepository {
    func search(_ query: SearchQuery, limit: Int) throws -> [ClipboardItem] {
        try search(query, limit: limit, offset: 0)
    }
}

extension ClipboardRepository: HistoryRepository {}

public protocol PasteServing: Sendable {
    func paste(item: ClipboardItem) async throws -> PasteOutcome
    func paste(item: ClipboardItem, mode: PasteMode) async throws -> PasteOutcome
    func paste(text: String) async throws -> PasteOutcome
}

public extension PasteServing {
    func paste(item: ClipboardItem, mode: PasteMode) async throws -> PasteOutcome {
        try await paste(item: item)
    }

    func paste(text: String) async throws -> PasteOutcome {
        throw TemplatePasteError.unsupported
    }
}

public enum TemplatePasteError: Error {
    case unsupported
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
    public private(set) var quickPasteSlots: [QuickPasteSlot] = []
    public private(set) var pasteStack: [PasteStackItem] = []
    public private(set) var templates: [SnippetTemplate] = []
    public private(set) var hasMoreItems = false

    @ObservationIgnored private let repository: any HistoryRepository
    @ObservationIgnored private let pasteService: any PasteServing
    @ObservationIgnored private let itemIntegrations: (any ItemIntegrationServing)?
    @ObservationIgnored private let visualService: (any ClipboardVisualServing)?
    @ObservationIgnored private var thumbnailTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var thumbnailRequestIDs: [UUID: UUID] = [:]
    @ObservationIgnored private var thumbnailPixelSizes: [UUID: Int] = [:]
    @ObservationIgnored private let historyPageSize = 150

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
        return contextActions(for: selectedItem)
    }

    public func applicationActions(for item: ClipboardItem) -> [ApplicationAction] {
        itemIntegrations?.availableActions(for: item) ?? []
    }

    public func contextActions(for item: ClipboardItem) -> [ItemContextAction] {
        itemIntegrations?.availableContextActions(for: item)
            ?? ItemContextAction.available(for: item.kind)
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
        case .copyOriginal, .copyPlainText, .copyMarkdownLink, .copyFilePath,
             .copyCleanText, .copyFirstLine, .copyURLs,
             .openLink, .openFile, .revealInFinder:
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
            let page = try repository.search(query, limit: historyPageSize + 1, offset: 0)
            let results = Array(page.prefix(historyPageSize))
            hasMoreItems = page.count > historyPageSize
            categories = try repository.allCategories()
            quickPasteSlots = try repository.quickPasteSlots()
            pasteStack = try repository.pasteStackItems()
            templates = try repository.templates()
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

    public func loadMore() async {
        guard hasMoreItems, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let query = SearchQuery(
                text: searchText,
                categoryID: selectedCategoryID,
                kind: selectedKind,
                favoritesOnly: favoritesOnly
            )
            let page = try repository.search(
                query,
                limit: historyPageSize + 1,
                offset: items.count
            )
            let nextItems = Array(page.prefix(historyPageSize))
            hasMoreItems = page.count > historyPageSize
            items.append(contentsOf: nextItems)
            if let visualService {
                for item in nextItems {
                    visuals[item.id] = visualService.metadataVisual(for: item)
                }
            }
        } catch {
            errorMessage = L10n.string("error.history.load")
        }
    }

    @discardableResult
    public func refreshCapturedItem(_ refreshedItem: ClipboardItem) -> Bool {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              selectedCategoryID == nil,
              selectedKind == nil,
              !favoritesOnly,
              let index = items.firstIndex(where: { $0.id == refreshedItem.id }),
              items[index].contentHash == refreshedItem.contentHash else {
            return false
        }

        items[index] = refreshedItem
        items.sort { lhs, rhs in
            let lhsOrder = lhs.lastUsedAt ?? lhs.updatedAt
            let rhsOrder = rhs.lastUsedAt ?? rhs.updatedAt
            if lhsOrder != rhsOrder { return lhsOrder > rhsOrder }
            return lhs.updatedAt > rhs.updatedAt
        }

        if let visualService {
            var descriptor = visualService.metadataVisual(for: refreshedItem)
            if let thumbnail = visuals[refreshedItem.id]?.thumbnail {
                descriptor = descriptor.replacingThumbnail(thumbnail)
            }
            visuals[refreshedItem.id] = descriptor
        }
        if selectedItemID == nil {
            selectedItemID = items.first?.id
        }
        errorMessage = nil
        return true
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
            try recordSuccessfulPaste(of: item)
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
            try recordSuccessfulPaste(of: item)
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
        await renameItem(item.id, to: title)
    }

    public func renameItem(_ id: UUID, to title: String?) async {
        do {
            try repository.rename(id, title: title)
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = L10n.string("error.rename")
        }
    }

    public func deleteSelection() async {
        guard let item = selectedItem else { return }
        await deleteItem(item.id)
    }

    public func deleteItem(_ id: UUID) async {
        do {
            try repository.delete(id)
            errorMessage = nil
            if selectedItemID == id {
                selectedItemID = nil
            }
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

    public func setQuickPasteSlot(_ index: Int, itemID: UUID) async {
        do {
            try repository.setQuickPasteSlot(index, itemID: itemID)
            quickPasteSlots = try repository.quickPasteSlots()
            errorMessage = nil
        } catch {
            errorMessage = L10n.string("error.quickPaste")
        }
    }

    public func clearQuickPasteSlot(_ index: Int) async {
        do {
            try repository.clearQuickPasteSlot(index)
            quickPasteSlots = try repository.quickPasteSlots()
            errorMessage = nil
        } catch {
            errorMessage = L10n.string("error.quickPaste")
        }
    }

    public func addToPasteStack(_ itemID: UUID) async {
        do {
            try repository.appendToPasteStack(itemID: itemID)
            pasteStack = try repository.pasteStackItems()
            errorMessage = nil
        } catch {
            errorMessage = L10n.string("error.pasteStack")
        }
    }

    public func removePasteStackItem(at position: Int) async {
        do {
            try repository.removePasteStackItem(at: position)
            pasteStack = try repository.pasteStackItems()
            errorMessage = nil
        } catch {
            errorMessage = L10n.string("error.pasteStack")
        }
    }

    public func clearPasteStack() async {
        do {
            try repository.clearPasteStack()
            pasteStack.removeAll()
            errorMessage = nil
        } catch {
            errorMessage = L10n.string("error.pasteStack")
        }
    }

    public func pasteNextStackItem() async {
        guard let entry = pasteStack.first else { return }

        do {
            lastPasteOutcome = try await pasteService.paste(item: entry.item)
            try recordSuccessfulPaste(of: entry.item)
            try repository.removePasteStackItem(at: entry.position)
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = L10n.string("error.paste")
        }
    }

    public func setTemporaryPolicy(
        for itemID: UUID,
        expiresAt: Date?,
        isOneTime: Bool
    ) async {
        do {
            try repository.setTemporaryPolicy(
                for: itemID,
                expiresAt: expiresAt,
                isOneTime: isOneTime
            )
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = L10n.string("error.temporary")
        }
    }

    public func createTemplate(from item: ClipboardItem) async {
        guard item.kind == .text || item.kind == .richText else { return }
        do {
            _ = try repository.createTemplate(title: item.displayTitle, body: item.searchText)
            templates = try repository.templates()
            errorMessage = nil
        } catch {
            errorMessage = L10n.string("error.template")
        }
    }

    public func pasteTemplate(_ template: SnippetTemplate, values: [String: String]) async {
        do {
            let text = SnippetTemplateRenderer.render(template.body, values: values)
            lastPasteOutcome = try await pasteService.paste(text: text)
            errorMessage = nil
        } catch {
            errorMessage = L10n.string("error.paste")
        }
    }

    public func pasteQuickSlot(_ index: Int) async {
        guard let slot = quickPasteSlots.first(where: { $0.index == index }) else {
            return
        }

        do {
            lastPasteOutcome = try await pasteService.paste(item: slot.item)
            try recordSuccessfulPaste(of: slot.item)
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = L10n.string("error.paste")
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

    private func recordSuccessfulPaste(of item: ClipboardItem) throws {
        try repository.markUsed(item.id)
        if item.isOneTime {
            try repository.delete(item.id)
        }
    }
}
