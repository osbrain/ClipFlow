import Foundation
import Testing
@testable import ClipFlowCore

@Suite("Clipboard normalization")
struct ClipboardNormalizerTests {
    private let normalizer = ClipboardNormalizer(
        maxRepresentationBytes: 1_000_000,
        maxCaptureBytes: 5_000_000
    )

    @Test("normalizes text line endings and hashes representations")
    func textCaptureNormalizesLineEndingsAndHashesRepresentations() throws {
        let capture = RawClipboardCapture(
            sourceAppName: "Notes",
            sourceBundleID: "com.apple.Notes",
            items: [
                RawClipboardItem(representations: [
                    RawClipboardRepresentation(
                        type: "public.utf8-plain-text",
                        data: Data("hello\r\nworld".utf8)
                    )
                ])
            ]
        )

        let result = try ClipboardNormalizer(
            maxRepresentationBytes: 1_000,
            maxCaptureBytes: 2_000
        ).normalize(capture)

        #expect(result.kind == .text)
        #expect(result.previewText == "hello\nworld")
        #expect(result.payloads.count == 1)
        #expect(result.contentHash.count == 64)
    }

    @Test("rejects an oversized representation without losing its valid sibling")
    func oversizedRepresentationDoesNotLoseValidSibling() throws {
        let capture = RawClipboardCapture(
            sourceAppName: "App",
            sourceBundleID: nil,
            items: [
                RawClipboardItem(representations: [
                    RawClipboardRepresentation(
                        type: "public.data",
                        data: Data(repeating: 1, count: 20)
                    ),
                    RawClipboardRepresentation(
                        type: "public.utf8-plain-text",
                        data: Data("ok".utf8)
                    )
                ])
            ]
        )

        let result = try ClipboardNormalizer(
            maxRepresentationBytes: 10,
            maxCaptureBytes: 100
        ).normalize(capture)

        #expect(result.payloads.map(\.type) == ["public.utf8-plain-text"])
        #expect(result.previewText == "ok")
    }

    @Test("rejects a capture with no usable payload")
    func emptyNormalizedCaptureIsRejected() {
        let capture = RawClipboardCapture(
            sourceAppName: "App",
            sourceBundleID: nil,
            items: [
                RawClipboardItem(representations: [
                    RawClipboardRepresentation(
                        type: "public.data",
                        data: Data(repeating: 1, count: 20)
                    )
                ])
            ]
        )

        #expect(throws: ClipboardNormalizationError.noUsablePayload) {
            try ClipboardNormalizer(
                maxRepresentationBytes: 10,
                maxCaptureBytes: 100
            ).normalize(capture)
        }
    }

    @Test("Finder companion formats remain a file")
    func finderRepresentationsClassifyAsFile() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/report.pdf")
        let result = try normalizer.normalize(capture(representations: [
            RawClipboardRepresentation(
                type: "public.file-url",
                data: fileURL.dataRepresentation
            ),
            RawClipboardRepresentation(
                type: "public.utf8-plain-text",
                data: Data(fileURL.path.utf8)
            ),
            RawClipboardRepresentation(
                type: "com.apple.finder.node",
                data: Data([1, 2, 3])
            )
        ]))

        #expect(result.kind == .file)
    }

    @Test("Browser URL and title formats remain a link")
    func browserRepresentationsClassifyAsLink() throws {
        let result = try normalizer.normalize(capture(representations: [
            RawClipboardRepresentation(
                type: "public.url",
                data: Data("https://example.com".utf8)
            ),
            RawClipboardRepresentation(
                type: "public.utf8-plain-text",
                data: Data("Example".utf8)
            ),
            RawClipboardRepresentation(
                type: "org.chromium.source-url",
                data: Data("https://example.com".utf8)
            )
        ]))

        #expect(result.kind == .link)
    }

    @Test("Plain web URL text becomes a link but prose remains text")
    func infersLinksFromPlainText() throws {
        #expect(try normalizeText("https://example.com/path").kind == .link)
        #expect(try normalizeText("mailto:hello@example.com").kind == .link)
        #expect(try normalizeText("Read https://example.com later").kind == .text)
    }

    @Test("Multiple files are files while heterogeneous items are mixed")
    func aggregatesSemanticItemKinds() throws {
        #expect(try normalizer.normalize(multiFileCapture()).kind == .file)
        #expect(try normalizer.normalize(fileAndTextCapture()).kind == .mixed)
    }

    @Test("Equivalent rich representations share a semantic hash")
    func equivalentRichRepresentationsShareHash() throws {
        let plain = try normalizer.normalize(capture(representations: [
            RawClipboardRepresentation(
                type: "public.utf8-plain-text",
                data: Data("Hello\r\nworld".utf8)
            )
        ]))
        let rich = try normalizer.normalize(capture(representations: [
            RawClipboardRepresentation(
                type: "public.html",
                data: Data("<p>Hello<br>world</p>".utf8)
            ),
            RawClipboardRepresentation(
                type: "public.rtf",
                data: Data("{\\rtf1 Hello\\line world}".utf8)
            ),
            RawClipboardRepresentation(
                type: "public.utf8-plain-text",
                data: Data("Hello\nworld".utf8)
            )
        ]))

        #expect(plain.contentHash == rich.contentHash)
    }

    @Test("Plain and advertised URLs share a canonical semantic hash")
    func equivalentURLRepresentationsShareHash() throws {
        let plain = try normalizeText("https://EXAMPLE.com/path?q=1")
        let advertised = try normalizer.normalize(capture(representations: [
            RawClipboardRepresentation(
                type: "public.url",
                data: Data("HTTPS://example.com/path?q=1".utf8)
            ),
            RawClipboardRepresentation(
                type: "public.utf8-plain-text",
                data: Data("Example page".utf8)
            )
        ]))

        #expect(plain.contentHash == advertised.contentHash)
    }

    @Test("File companion formats do not change semantic identity")
    func equivalentFileRepresentationsShareHash() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/../tmp/report.pdf")
        let canonicalURL = URL(fileURLWithPath: "/tmp/report.pdf")
        let first = try normalizer.normalize(capture(representations: [
            RawClipboardRepresentation(
                type: "public.file-url",
                data: fileURL.dataRepresentation
            ),
            RawClipboardRepresentation(
                type: "com.apple.finder.node",
                data: Data([1, 2, 3])
            )
        ]))
        let second = try normalizer.normalize(capture(representations: [
            RawClipboardRepresentation(
                type: "public.file-url",
                data: canonicalURL.dataRepresentation
            ),
            RawClipboardRepresentation(
                type: "public.utf8-plain-text",
                data: Data(canonicalURL.path.utf8)
            )
        ]))

        #expect(first.contentHash == second.contentHash)
    }

    @Test("Distinct semantic values keep distinct hashes")
    func distinctValuesKeepDistinctHashes() throws {
        #expect(try normalizeText("Alpha").contentHash != normalizeText("alpha").contentHash)
        #expect(
            try normalizeText("https://example.com/a").contentHash
                != normalizeText("https://example.com/b").contentHash
        )
    }

    private func capture(
        representations: [RawClipboardRepresentation]
    ) -> RawClipboardCapture {
        RawClipboardCapture(
            sourceAppName: "Test",
            sourceBundleID: "local.clipflow.tests",
            items: [RawClipboardItem(representations: representations)]
        )
    }

    private func normalizeText(_ value: String) throws -> NormalizedCapture {
        try normalizer.normalize(capture(representations: [
            RawClipboardRepresentation(
                type: "public.utf8-plain-text",
                data: Data(value.utf8)
            )
        ]))
    }

    private func multiFileCapture() -> RawClipboardCapture {
        RawClipboardCapture(
            sourceAppName: "Finder",
            sourceBundleID: "com.apple.finder",
            items: ["a.txt", "b.txt"].map { name in
                let url = URL(fileURLWithPath: "/tmp/\(name)")
                return RawClipboardItem(representations: [
                    RawClipboardRepresentation(
                        type: "public.file-url",
                        data: url.dataRepresentation
                    ),
                    RawClipboardRepresentation(
                        type: "public.utf8-plain-text",
                        data: Data(url.path.utf8)
                    )
                ])
            }
        )
    }

    private func fileAndTextCapture() -> RawClipboardCapture {
        RawClipboardCapture(
            sourceAppName: "Test",
            sourceBundleID: nil,
            items: [
                RawClipboardItem(representations: [
                    RawClipboardRepresentation(
                        type: "public.file-url",
                        data: URL(fileURLWithPath: "/tmp/a.txt").dataRepresentation
                    )
                ]),
                RawClipboardItem(representations: [
                    RawClipboardRepresentation(
                        type: "public.utf8-plain-text",
                        data: Data("note".utf8)
                    )
                ])
            ]
        )
    }
}
