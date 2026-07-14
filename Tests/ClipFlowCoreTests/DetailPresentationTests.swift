import ClipFlowCore
import Testing
@testable import ClipFlowUI

@Suite("Detail presentation")
struct DetailPresentationTests {
    @Test("visible fields preserve the product metadata order")
    func visibleFieldsPreserveOrder() {
        let visibility = DetailFieldVisibility(
            showsSource: true,
            showsKind: false,
            showsCreated: true,
            showsLastUsed: false,
            showsSize: true,
            showsFormatting: true
        )

        #expect(visibility.visibleFields == [.source, .created, .size, .formatting])
    }

    @Test("clipboard kinds choose deterministic local preview modes", arguments: [
        (ClipboardKind.text, DetailPreviewMode.text),
        (.richText, .text),
        (.image, .image),
        (.file, .file),
        (.link, .link),
        (.mixed, .mixed),
        (.unknown, .unknown)
    ])
    func previewModeMapping(kind: ClipboardKind, expected: DetailPreviewMode) {
        #expect(kind.detailPreviewMode == expected)
    }

    @Test("formatting is available only for rich or mixed content", arguments: [
        (ClipboardKind.text, false),
        (.richText, true),
        (.image, false),
        (.file, false),
        (.link, false),
        (.mixed, true),
        (.unknown, false)
    ])
    func formattingAvailability(kind: ClipboardKind, expected: Bool) {
        #expect(kind.hasFormatting == expected)
    }
}
