import ClipFlowCore
import Testing
@testable import ClipFlowUI

@Suite("Item context actions")
struct ItemContextActionTests {
    @Test("each clipboard kind exposes its exact content action matrix")
    func actionMatrix() {
        #expect(ItemContextAction.available(for: .text) == [
            .pasteOriginal, .pastePlainText
        ])
        #expect(ItemContextAction.available(for: .richText) == [
            .pasteOriginal, .pastePlainText, .quickLook
        ])
        #expect(ItemContextAction.available(for: .link) == [
            .pasteOriginal, .openLink, .pastePlainText
        ])
        #expect(ItemContextAction.available(for: .file) == [
            .pasteOriginal, .pasteFilePath, .openFile, .revealInFinder, .quickLook
        ])
        #expect(ItemContextAction.available(for: .image) == [
            .pasteOriginal, .quickLook
        ])
        #expect(ItemContextAction.available(for: .mixed) == [
            .pasteOriginal, .pastePlainText, .quickLook
        ])
        #expect(ItemContextAction.available(for: .unknown) == [
            .pasteOriginal, .quickLook
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
    }
}
