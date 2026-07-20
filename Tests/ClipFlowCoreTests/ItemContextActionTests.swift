import ClipFlowCore
import Testing
@testable import ClipFlowUI

@Suite("Item context actions")
struct ItemContextActionTests {
    @Test("each clipboard kind exposes its exact content action matrix")
    func actionMatrix() {
        #expect(ItemContextAction.available(for: .text) == [
            .pasteOriginal, .pastePlainText,
            .copyOriginal, .copyPlainText, .copyCleanText,
            .copyFirstLine, .copyURLs, .quickLook
        ])
        #expect(ItemContextAction.available(for: .richText) == [
            .pasteOriginal, .pastePlainText,
            .copyOriginal, .copyPlainText, .copyCleanText,
            .copyFirstLine, .copyURLs, .quickLook
        ])
        #expect(ItemContextAction.available(for: .link) == [
            .pasteOriginal, .openLink, .pastePlainText,
            .copyOriginal, .copyPlainText, .copyMarkdownLink,
            .copyCleanText, .copyFirstLine, .copyURLs, .quickLook
        ])
        #expect(ItemContextAction.available(for: .file) == [
            .pasteOriginal, .pasteFilePath, .openFile, .revealInFinder,
            .copyOriginal, .copyFilePath, .quickLook
        ])
        #expect(ItemContextAction.available(for: .image) == [
            .pasteOriginal, .copyOriginal, .quickLook
        ])
        #expect(ItemContextAction.available(for: .mixed) == [
            .pasteOriginal, .pastePlainText,
            .copyOriginal, .copyPlainText, .copyCleanText,
            .copyFirstLine, .copyURLs, .quickLook
        ])
        #expect(ItemContextAction.available(for: .unknown) == [
            .pasteOriginal, .copyOriginal, .quickLook
        ])
    }

    @Test("every context action has stable presentation metadata")
    func presentationMetadata() {
        for action in ItemContextAction.allCases {
            #expect(!action.localizationKey.isEmpty)
            #expect(!action.symbolName.isEmpty)
        }
        #expect(ItemContextAction.openLink.localizationKey == "contextAction.openLink")
        #expect(ItemContextAction.revealInFinder.symbolName == "folder")
        #expect(
            ItemContextAction.pasteOriginal.titleKey(for: .file) ==
                "contextAction.pasteOriginal.file"
        )
        #expect(
            ItemContextAction.pasteOriginal.titleKey(for: .link) ==
                "contextAction.pasteOriginal.link"
        )
        #expect(
            ItemContextAction.openLink.titleKey(for: .link) ==
                "contextAction.openLink"
        )
        #expect(ItemContextAction.copyPlainText.isContentOperation)
        #expect(ItemContextAction.pastePlainText.symbolName == "doc.plaintext")
        #expect(ItemContextAction.copyPlainText.symbolName == "doc.text")
        #expect(ItemContextAction.copyMarkdownLink.isContentOperation)
        #expect(!ItemContextAction.openFile.isContentOperation)
    }
}
