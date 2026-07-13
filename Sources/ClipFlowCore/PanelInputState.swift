import Foundation

public enum PanelFocus: Equatable, Sendable {
    case search
    case historyList
    case details
    case textEditor
}

public enum PanelInputCommand: Equatable, Sendable {
    case escape
    case moveUp
    case moveDown
    case confirm
    case copy
    case preview
}

public enum PanelInputAction: Equatable, Sendable {
    case none
    case clearSearch
    case dismiss
    case endEditing
    case selectPrevious
    case selectNext
    case pasteSelection
    case copySelection
    case previewSelection
}

public struct PanelInputState: Equatable, Sendable {
    public var isVisible: Bool
    public var searchText: String
    public var focus: PanelFocus

    public init(isVisible: Bool, searchText: String, focus: PanelFocus) {
        self.isVisible = isVisible
        self.searchText = searchText
        self.focus = focus
    }

    public func handle(_ command: PanelInputCommand) -> PanelInputAction {
        switch command {
        case .escape:
            if focus == .textEditor { return .endEditing }
            if !searchText.isEmpty { return .clearSearch }
            return isVisible ? .dismiss : .none
        case .moveUp:
            return focus == .textEditor ? .none : .selectPrevious
        case .moveDown:
            return focus == .textEditor ? .none : .selectNext
        case .confirm:
            return focus == .textEditor ? .none : .pasteSelection
        case .copy:
            return focus == .textEditor ? .none : .copySelection
        case .preview:
            return focus == .textEditor ? .none : .previewSelection
        }
    }
}

