import ClipFlowCore
import Foundation
import Observation

enum PanelFocusTarget: Hashable {
    case search
    case history(UUID)
    case browser(String)
}

public enum PanelListFocusRequest: Equatable, Sendable {
    case history(UUID)
    case browser(String)

    public var historyItemID: UUID? {
        guard case let .history(id) = self else { return nil }
        return id
    }

    public var browserTabID: String? {
        guard case let .browser(id) = self else { return nil }
        return id
    }
}

@MainActor
@Observable
public final class PanelInputStateStore {
    public var focus: PanelCommandFocus = .search
    public var searchText = ""
    public var isPresentingSheet = false
    public var isPresentingOnboarding = false
    public var isPanelVisible = false
    public private(set) var requestedListFocus: PanelListFocusRequest?

    public init() {}

    public var commandContext: PanelCommandContext {
        PanelCommandContext(
            focus: focus,
            hasSearchText: !searchText.isEmpty,
            isPresentingSheet: isPresentingSheet
        )
    }

    public func requestHistoryFocus(_ id: UUID?) {
        requestedListFocus = id.map(PanelListFocusRequest.history)
    }

    public func requestBrowserFocus(_ id: String?) {
        requestedListFocus = id.map(PanelListFocusRequest.browser)
    }

    public func clearListFocusRequest() {
        requestedListFocus = nil
    }
}

public struct VisualAcceptanceConfiguration: Equatable, Sendable {
    public let token: String
    public let dataDirectory: String
    public let appearanceMode: ClipFlowAppearanceMode
    public let listDensity: ClipFlowListDensity
    public let browserTabManagementEnabled: Bool
    public let selectedKind: ClipboardKind?
    public let showsOnboarding: Bool
    public let accessibilityTrusted: Bool

    public static func isProbe(arguments: [String]) -> Bool {
        arguments.contains("--clipflow-acceptance-probe")
    }

    public static func validated(
        environment: [String: String],
        arguments: [String]
    ) -> Self? {
        guard environment["CLIPFLOW_VISUAL_ACCEPTANCE"] == "1",
              let token = environment["CLIPFLOW_ACCEPTANCE_TOKEN"],
              !token.isEmpty,
              let dataDirectory = environment["CLIPFLOW_DEVELOPMENT_DATA_DIR"],
              !dataDirectory.isEmpty else {
            return nil
        }

        let requestedAppearance = environment["CLIPFLOW_APPEARANCE_MODE"]
            ?? argumentValue(for: "-appearanceMode", in: arguments)
        let appearanceMode = requestedAppearance.flatMap(ClipFlowAppearanceMode.init(rawValue:))
            ?? (environment["AppleInterfaceStyle"] == "Dark" ? .dark : .light)

        let requestedDensity = environment["CLIPFLOW_LIST_DENSITY"]
            ?? argumentValue(for: "-listDensity", in: arguments)
        let listDensity = requestedDensity.flatMap(ClipFlowListDensity.init(rawValue:))
            ?? .comfortable

        let browserValue = environment["CLIPFLOW_BROWSER_ENABLED"]
            ?? argumentValue(for: "-browserTabManagementEnabled", in: arguments)

        return Self(
            token: token,
            dataDirectory: dataDirectory,
            appearanceMode: appearanceMode,
            listDensity: listDensity,
            browserTabManagementEnabled: browserValue.map(parseBoolean) ?? true,
            selectedKind: environment["CLIPFLOW_SELECTED_KIND"]
                .flatMap(ClipboardKind.init(rawValue:)),
            showsOnboarding: environment["CLIPFLOW_SHOW_ONBOARDING"].map(parseBoolean)
                ?? false,
            accessibilityTrusted: environment["CLIPFLOW_ACCESSIBILITY_GRANTED"]
                .map(parseBoolean) ?? false
        )
    }

    private static func argumentValue(for key: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: key),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func parseBoolean(_ value: String) -> Bool {
        switch value.lowercased() {
        case "1", "true", "yes": true
        default: false
        }
    }
}
