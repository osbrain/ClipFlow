import ClipFlowCore
import Testing
@testable import ClipFlowUI

@Suite("Clipboard kind presentation")
struct ClipboardKindPresentationTests {
    @Test("text uses the text symbol")
    func textSymbol() {
        #expect(ClipboardKind.text.presentation.symbolName == "text.alignleft")
    }

    @Test("rich text uses the rich text document symbol")
    func richTextSymbol() {
        #expect(ClipboardKind.richText.presentation.symbolName == "doc.richtext")
    }

    @Test("image uses the photo symbol")
    func imageSymbol() {
        #expect(ClipboardKind.image.presentation.symbolName == "photo")
    }

    @Test("file uses the document symbol")
    func fileSymbol() {
        #expect(ClipboardKind.file.presentation.symbolName == "doc")
    }

    @Test("link uses the link symbol")
    func linkSymbol() {
        #expect(ClipboardKind.link.presentation.symbolName == "link")
    }

    @Test("image and text use distinct accents")
    func imageAndTextAccentsDiffer() {
        #expect(ClipboardKind.image.presentation.accent != ClipboardKind.text.presentation.accent)
    }

    @Test("mixed uses a stable presentation")
    func mixedPresentation() {
        #expect(ClipboardKind.mixed.presentation == ClipboardKindPresentation(
            symbolName: "square.stack.3d.up",
            accent: .pink
        ))
    }

    @Test("unknown uses a stable presentation")
    func unknownPresentation() {
        #expect(ClipboardKind.unknown.presentation == ClipboardKindPresentation(
            symbolName: "questionmark.square.dashed",
            accent: .gray
        ))
    }
}
