import ClipFlowCore
import Testing
@testable import ClipFlowUI

@Suite("Detail presentation")
struct DetailPresentationTests {
    @Test("detail previews use bounded summaries for every content mode")
    func boundedPreviewMetrics() {
        #expect(DetailPreviewLayout.lineLimit(for: .text) == 8)
        #expect(DetailPreviewLayout.lineLimit(for: .link) == 5)
        #expect(DetailPreviewLayout.lineLimit(for: .file) == 5)
        #expect(DetailPreviewLayout.lineLimit(for: .mixed) == 6)
        #expect(DetailPreviewLayout.lineLimit(for: .unknown) == 5)
        #expect(DetailPreviewLayout.lineLimit(for: .image) == nil)
        #expect(DetailPreviewLayout.imageMaximumHeight == 200)
    }

    @Test("quick look is promoted from the action stack into the preview card")
    func promotesQuickLookIntoPreviewCard() {
        #expect(
            DetailActionPresentation.stackActions(from: [
                .pasteOriginal, .pastePlainText, .quickLook
            ]) == [.pasteOriginal, .pastePlainText]
        )
    }

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
