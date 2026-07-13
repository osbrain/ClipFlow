import Foundation
import Testing
@testable import ClipFlowCore

@Suite("Clipboard item model")
struct ModelsTests {
    @Test("keeps stable identity and falls back to its preview title")
    func clipboardItemKeepsStableIdentity() {
        let id = UUID()
        let item = ClipboardItem(
            id: id,
            createdAt: .distantPast,
            updatedAt: .distantPast,
            appName: "Finder",
            bundleID: "com.apple.finder",
            kind: .text,
            previewText: "hello",
            searchText: "hello",
            byteSize: 5,
            contentHash: "abc",
            isFavorite: false,
            lastUsedAt: nil,
            customTitle: nil,
            hasExternalPayload: false
        )

        #expect(item.id == id)
        #expect(item.displayTitle == "hello")
    }
}
