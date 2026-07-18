import ClipFlowSystem
import Foundation
import Observation

public protocol BrowserTabServing: Sendable {
    func status(for browser: BrowserKind) -> BrowserAutomationStatus
    func tabs(for browser: BrowserKind) throws -> [BrowserTab]
    func snapshot(for browser: BrowserKind) -> BrowserTabSnapshot
    func activate(_ tab: BrowserTab) throws
}

extension BrowserAutomation: BrowserTabServing {}

public extension BrowserTabServing {
    func snapshot(for browser: BrowserKind) -> BrowserTabSnapshot {
        let status = status(for: browser)
        guard status == .authorized else {
            return BrowserTabSnapshot(status: status)
        }
        do {
            return BrowserTabSnapshot(status: status, tabs: try tabs(for: browser))
        } catch BrowserAutomationError.notAuthorized {
            return BrowserTabSnapshot(status: .notAuthorized)
        } catch {
            return BrowserTabSnapshot(status: .notAuthorized)
        }
    }
}

@MainActor
@Observable
public final class BrowserTabModel {
    public var isShowing = false
    public var searchText = ""
    public private(set) var tabs: [BrowserTab] = []
    public private(set) var statuses: [BrowserKind: BrowserAutomationStatus] = [:]
    public var selectedTabID: String?
    public private(set) var errorMessage: String?

    @ObservationIgnored private let service: any BrowserTabServing

    public init(service: any BrowserTabServing) {
        self.service = service
    }

    public var filteredTabs: [BrowserTab] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tabs }
        return tabs.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
                $0.url.localizedCaseInsensitiveContains(query)
        }
    }

    public var selectedTab: BrowserTab? {
        guard let selectedTabID else { return nil }
        return filteredTabs.first { $0.id == selectedTabID }
    }

    public func refresh() async {
        var collected: [BrowserTab] = []
        var nextStatuses: [BrowserKind: BrowserAutomationStatus] = [:]
        for browser in BrowserKind.allCases {
            let snapshot = service.snapshot(for: browser)
            nextStatuses[browser] = snapshot.status
            collected.append(contentsOf: snapshot.tabs)
        }
        statuses = nextStatuses
        tabs = collected.sorted {
            if $0.browser != $1.browser { return $0.browser.rawValue < $1.browser.rawValue }
            if $0.windowIndex != $1.windowIndex { return $0.windowIndex < $1.windowIndex }
            return $0.tabIndex < $1.tabIndex
        }
        if selectedTab == nil { selectedTabID = filteredTabs.first?.id }
        errorMessage = nil
    }

    public func activateSelection() async {
        guard let selectedTab else { return }
        do {
            try service.activate(selectedTab)
            errorMessage = nil
        } catch {
            await refresh()
            errorMessage = L10n.string("error.browser.activate")
        }
    }
}
