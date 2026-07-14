import ClipFlowCore
import Foundation

public enum HistoryFilter: Equatable, Sendable {
    case all
    case favorites
    case kind(ClipboardKind)
    case category(UUID)
    case browserTabs

    public var repositoryState: HistoryRepositoryFilterState {
        switch self {
        case .all, .browserTabs:
            HistoryRepositoryFilterState(
                kind: nil,
                categoryID: nil,
                favoritesOnly: false
            )
        case .favorites:
            HistoryRepositoryFilterState(
                kind: nil,
                categoryID: nil,
                favoritesOnly: true
            )
        case let .kind(kind):
            HistoryRepositoryFilterState(
                kind: kind,
                categoryID: nil,
                favoritesOnly: false
            )
        case let .category(categoryID):
            HistoryRepositoryFilterState(
                kind: nil,
                categoryID: categoryID,
                favoritesOnly: false
            )
        }
    }
}

public struct HistoryRepositoryFilterState: Equatable, Sendable {
    public let kind: ClipboardKind?
    public let categoryID: UUID?
    public let favoritesOnly: Bool

    public init(kind: ClipboardKind?, categoryID: UUID?, favoritesOnly: Bool) {
        self.kind = kind
        self.categoryID = categoryID
        self.favoritesOnly = favoritesOnly
    }
}
