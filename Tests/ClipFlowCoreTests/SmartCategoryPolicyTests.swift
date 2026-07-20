import Foundation
import Testing
import ClipFlowCore
@testable import ClipFlowUI

@Suite("Smart category policy")
struct SmartCategoryPolicyTests {
    @Test("disabled policy leaves captures uncategorized")
    func disabledPolicyLeavesCapturesUncategorized() {
        let policy = SmartCategoryPolicy(isEnabled: false)

        #expect(policy.suggestion(for: Self.capture(kind: .link, text: "https://example.com")) == nil)
    }

    @Test("kind based captures map to stable smart categories")
    func kindBasedCapturesMapToStableCategories() {
        let policy = SmartCategoryPolicy(isEnabled: true)

        #expect(policy.suggestion(for: Self.capture(kind: .link)) == .link)
        #expect(policy.suggestion(for: Self.capture(kind: .image)) == .image)
        #expect(policy.suggestion(for: Self.capture(kind: .file)) == .file)
    }

    @Test("text rules classify code finance todo and work notes")
    func textRulesClassifyCommonWorkflows() {
        let policy = SmartCategoryPolicy(isEnabled: true)

        #expect(policy.suggestion(for: Self.capture(text: "func paste() { return true }")) == .code)
        #expect(policy.suggestion(for: Self.capture(text: "发票金额 ¥128，等待报销")) == .finance)
        #expect(policy.suggestion(for: Self.capture(text: "TODO: follow up with Alice tomorrow")) == .todo)
        #expect(policy.suggestion(for: Self.capture(app: "Feishu", text: "项目会议纪要和需求讨论")) == .work)
    }

    private static func capture(
        app: String = "Notes",
        bundleID: String? = "com.apple.Notes",
        kind: ClipboardKind = .text,
        text: String = "hello"
    ) -> NormalizedCapture {
        NormalizedCapture(
            sourceAppName: app,
            sourceBundleID: bundleID,
            kind: kind,
            previewText: text,
            searchText: text.lowercased(),
            byteSize: text.utf8.count,
            contentHash: UUID().uuidString,
            payloads: []
        )
    }
}
