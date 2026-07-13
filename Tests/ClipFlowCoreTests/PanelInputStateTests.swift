import Testing
@testable import ClipFlowCore

@Suite("Floating panel input state")
struct PanelInputStateTests {
    @Test("Escape clears search before dismissing the panel")
    func escapeClearsSearchBeforeDismissal() {
        var state = PanelInputState(
            isVisible: true,
            searchText: "abc",
            focus: .search
        )

        #expect(state.handle(.escape) == .clearSearch)
        state.searchText = ""
        #expect(state.handle(.escape) == .dismiss)
    }

    @Test("Escape ends text editing before dismissing")
    func escapeEndsEditingFirst() {
        let state = PanelInputState(
            isVisible: true,
            searchText: "",
            focus: .textEditor
        )

        #expect(state.handle(.escape) == .endEditing)
    }
}
