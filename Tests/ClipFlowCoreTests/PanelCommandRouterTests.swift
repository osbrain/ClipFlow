import Testing
import Foundation
@testable import ClipFlowUI

@Suite("Panel command router")
struct PanelCommandRouterTests {
    private let router = PanelCommandRouter()

    @Test("space previews only while the history list owns focus")
    func spaceBehavior() {
        #expect(router.action(for: .space, context: .init(focus: .list)) == .previewSelection)
        #expect(router.action(for: .space, context: .init(focus: .search)) == .passThrough)
        #expect(router.action(for: .space, context: .init(focus: .editing)) == .passThrough)
    }

    @Test("escape clears a nonempty search before dismissing")
    func escapeBehavior() {
        #expect(
            router.action(
                for: .escape,
                context: .init(focus: .search, hasSearchText: true)
            ) == .clearSearch
        )
        #expect(
            router.action(
                for: .escape,
                context: .init(focus: .list, hasSearchText: false)
            ) == .dismissPanel
        )
        #expect(
            router.action(
                for: .escape,
                context: .init(focus: .editing, isPresentingSheet: true)
            ) == .passThrough
        )
    }

    @Test("return variants paste using explicit modes outside editing")
    func returnBehavior() {
        #expect(router.action(for: .returnKey, context: .init(focus: .list)) == .pasteSelection)
        #expect(router.action(for: .commandReturn, context: .init(focus: .list)) == .pasteSelectionAsPlainText)
        #expect(router.action(for: .returnKey, context: .init(focus: .search)) == .passThrough)
        #expect(router.action(for: .returnKey, context: .init(focus: .details)) == .passThrough)
        #expect(router.action(for: .returnKey, context: .init(focus: .editing)) == .passThrough)
        #expect(router.action(for: .commandReturn, context: .init(focus: .editing)) == .passThrough)
    }

    @Test("arrows navigate only while a list row owns focus")
    func arrowBehavior() {
        #expect(router.action(for: .moveUp, context: .init(focus: .search)) == .passThrough)
        #expect(router.action(for: .moveDown, context: .init(focus: .list)) == .selectNext)
        #expect(router.action(for: .moveUp, context: .init(focus: .details)) == .passThrough)
        #expect(router.action(for: .moveUp, context: .init(focus: .editing)) == .passThrough)
        #expect(router.action(for: .moveDown, context: .init(focus: .editing)) == .passThrough)
    }
}

@Suite("Panel event routing scope")
struct PanelEventRoutingScopeTests {
    @Test("routes only events targeting the key floating panel")
    func routesOnlyKeyPanelEvents() {
        #expect(PanelEventRoutingScope.shouldRoute(
            isPanelKeyWindow: true,
            eventTargetsPanel: true
        ))
        #expect(!PanelEventRoutingScope.shouldRoute(
            isPanelKeyWindow: false,
            eventTargetsPanel: true
        ))
        #expect(!PanelEventRoutingScope.shouldRoute(
            isPanelKeyWindow: true,
            eventTargetsPanel: false
        ))
        #expect(!PanelEventRoutingScope.shouldRoute(
            isPanelKeyWindow: false,
            eventTargetsPanel: false
        ))
    }
}

@Suite("Panel list focus requests")
@MainActor
struct PanelListFocusRequestTests {
    @Test("focused rows expose the matching acted-on selection")
    func focusedRowsMapToSelections() {
        let historyID = UUID()
        let browserID = "safari:0:0:https://example.com"

        #expect(PanelListFocusRequest.history(historyID).historyItemID == historyID)
        #expect(PanelListFocusRequest.history(historyID).browserTabID == nil)
        #expect(PanelListFocusRequest.browser(browserID).browserTabID == browserID)
        #expect(PanelListFocusRequest.browser(browserID).historyItemID == nil)
    }

    @Test("arrow selection requests focus for the same row ID")
    func stateStoreCarriesArrowFocusRequests() {
        let store = PanelInputStateStore()
        let historyID = UUID()
        let browserID = "chrome:0:1:https://openai.com"

        store.requestHistoryFocus(historyID)
        #expect(store.requestedListFocus == .history(historyID))

        store.requestBrowserFocus(browserID)
        #expect(store.requestedListFocus == .browser(browserID))

        store.clearListFocusRequest()
        #expect(store.requestedListFocus == nil)
    }
}
