public enum PanelCommand: Equatable, Sendable {
    case space
    case returnKey
    case commandReturn
    case escape
    case moveUp
    case moveDown
}

public enum PanelCommandAction: Equatable, Sendable {
    case passThrough
    case previewSelection
    case pasteSelection
    case pasteSelectionAsPlainText
    case clearSearch
    case dismissPanel
    case selectPrevious
    case selectNext
}

public enum PanelCommandFocus: Equatable, Sendable {
    case search
    case list
    case details
    case editing
}

public struct PanelCommandContext: Equatable, Sendable {
    public let focus: PanelCommandFocus
    public let hasSearchText: Bool
    public let isPresentingSheet: Bool

    public init(
        focus: PanelCommandFocus,
        hasSearchText: Bool = false,
        isPresentingSheet: Bool = false
    ) {
        self.focus = focus
        self.hasSearchText = hasSearchText
        self.isPresentingSheet = isPresentingSheet
    }
}

public struct PanelCommandRouter: Sendable {
    public init() {}

    public func action(
        for command: PanelCommand,
        context: PanelCommandContext
    ) -> PanelCommandAction {
        if context.isPresentingSheet || context.focus == .editing {
            return .passThrough
        }

        switch command {
        case .escape:
            return context.hasSearchText ? .clearSearch : .dismissPanel
        case .space, .returnKey, .commandReturn, .moveUp, .moveDown:
            guard context.focus == .list else { return .passThrough }
            switch command {
            case .space: return .previewSelection
            case .returnKey: return .pasteSelection
            case .commandReturn: return .pasteSelectionAsPlainText
            case .moveUp: return .selectPrevious
            case .moveDown: return .selectNext
            case .escape: return .passThrough
            }
        }
    }
}

public enum PanelEventRoutingScope {
    public static func shouldRoute(
        isPanelKeyWindow: Bool,
        eventTargetsPanel: Bool
    ) -> Bool {
        isPanelKeyWindow && eventTargetsPanel
    }
}
