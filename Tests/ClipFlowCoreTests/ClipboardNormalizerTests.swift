import Foundation
import Testing
@testable import ClipFlowCore

@Suite("Clipboard normalization")
struct ClipboardNormalizerTests {
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
}
