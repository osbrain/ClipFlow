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

    @Test("sequential paste exposes one dedicated global shortcut")
    func sequentialPasteShortcut() {
        #expect(PasteStackHotKey.next.rawValue == "optionShiftCommandV")
    }

    @Test("each Carbon event invokes only its owning global shortcut")
    func eventRoutingIsIsolated() {
        #expect(GlobalHotKeyEventRouter.action(signature: 0x434c5046, id: 1) == .togglePanel)
        #expect(GlobalHotKeyEventRouter.action(signature: 0x434c5150, id: 4) == .quickPaste(4))
        #expect(GlobalHotKeyEventRouter.action(signature: 0x43505354, id: 1) == .pasteNextStackItem)
        #expect(GlobalHotKeyEventRouter.action(signature: 0x434c5046, id: 4) == nil)
        #expect(GlobalHotKeyEventRouter.action(signature: 0x43505354, id: 2) == nil)
    }
}
