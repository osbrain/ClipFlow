import Testing
@testable import ClipFlowUI

@Suite("Content action transformer")
struct ContentActionTransformerTests {
    @Test("cleaned text trims and collapses repeated whitespace")
    func cleanedTextCollapsesWhitespace() {
        let source = "  Alpha \n\n Beta\t\tGamma  \n Delta  "

        #expect(ContentActionTransformer.cleanedText(from: source) == "Alpha Beta Gamma Delta")
    }

    @Test("first line uses the first non-empty trimmed line")
    func firstLineUsesFirstNonEmptyLine() {
        let source = "\n   \n  ClipFlow title  \nBody line"

        #expect(ContentActionTransformer.firstLine(from: source) == "ClipFlow title")
    }

    @Test("URL extraction copies one URL per line without surrounding punctuation")
    func urlExtractionCopiesOnePerLine() {
        let source = "See https://example.com/docs, then http://clip.flow/a?b=1."

        #expect(
            ContentActionTransformer.extractedURLs(from: source) ==
                "https://example.com/docs\nhttp://clip.flow/a?b=1"
        )
    }

    @Test("Markdown link uses a safe title and destination")
    func markdownLinkUsesSafeTitleAndDestination() {
        #expect(
            ContentActionTransformer.markdownLink(
                title: "Clip [Flow]",
                urlString: "https://github.com/osbrain/ClipFlow"
            ) == "[Clip \\[Flow\\]](https://github.com/osbrain/ClipFlow)"
        )
    }
}
