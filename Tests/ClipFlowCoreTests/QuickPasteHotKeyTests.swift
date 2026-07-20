import ClipFlowSystem
import Testing

@Suite("Quick paste global shortcuts")
struct QuickPasteHotKeyTests {
    @Test("every quick paste slot has a global Option-Command digit shortcut")
    func slotShortcutCoverage() {
        #expect(QuickPasteHotKey.allCases.map(\.slotIndex) == Array(1...9))
        #expect(QuickPasteHotKey(slotIndex: 1) == .slot1)
        #expect(QuickPasteHotKey(slotIndex: 9) == .slot9)
        #expect(QuickPasteHotKey(slotIndex: 10) == nil)
    }
}
