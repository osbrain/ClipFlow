import ClipFlowCore
import Foundation
import Testing
@testable import ClipFlowUI

@Suite("Status menu presentation")
struct StatusMenuPresentationTests {
    @MainActor
    @Test("defers panel presentation until status menu tracking has ended")
    func defersPanelPresentation() async {
        var presentationCount = 0

        StatusMenuPanelPresentation.afterMenuCloses {
            presentationCount += 1
        }

        #expect(presentationCount == 0)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        #expect(presentationCount == 1)
    }

    @Test("shows three recent items with source and kind metadata")
    func recentItemsAreCompactAndOrdered() {
        let newest = Self.item(
            preview: "Project handoff notes\nwith a second line",
            appName: "Notes",
            kind: .text
        )
        let second = Self.item(
            preview: "clipflow-release.zip",
            appName: "Finder",
            kind: .file
        )
        let third = Self.item(
            preview: "https://example.com",
            appName: "Safari",
            kind: .link
        )
        let hidden = Self.item(
            preview: "Older item",
            appName: "WeChat",
            kind: .richText
        )

        let presentation = StatusMenuPresentation(
            items: [newest, second, third, hidden],
            pasteDestinationName: "Notes"
        )

        #expect(presentation.recordCount == 4)
        #expect(presentation.recentItems.map(\.id) == [newest.id, second.id, third.id])
        #expect(presentation.recentItems[0].title == "Project handoff notes with a second line")
        #expect(presentation.recentItems[1].sourceName == "Finder")
        #expect(presentation.recentItems[1].kind == .file)
        #expect(presentation.recentItems[1].symbolName == "doc")
        #expect(presentation.pasteDestinationName == "Notes")
    }

    @Test("uses the source name when clipboard preview is empty")
    func emptyPreviewHasAFallbackTitle() {
        let item = Self.item(preview: " \n\t ", appName: "Finder", kind: .file)

        let presentation = StatusMenuPresentation(
            items: [item],
            pasteDestinationName: nil
        )

        #expect(presentation.recentItems[0].title == "Finder")
    }

    private static func item(
        preview: String,
        appName: String,
        kind: ClipboardKind
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            createdAt: .distantPast,
            updatedAt: .distantPast,
            appName: appName,
            bundleID: nil,
            kind: kind,
            previewText: preview,
            searchText: preview,
            byteSize: preview.utf8.count,
            contentHash: UUID().uuidString,
            isFavorite: false,
            lastUsedAt: nil,
            customTitle: nil,
            hasExternalPayload: false
        )
    }
}
