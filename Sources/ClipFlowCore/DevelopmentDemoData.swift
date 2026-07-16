import Foundation

public struct DevelopmentDemoFixture: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let capturedAt: Date
    public let expectedKind: ClipboardKind
    public let capture: RawClipboardCapture

    public init(
        id: UUID,
        capturedAt: Date,
        expectedKind: ClipboardKind,
        capture: RawClipboardCapture
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.expectedKind = expectedKind
        self.capture = capture
    }
}

public enum DevelopmentDemoData {
    public static func fixtures(
        now: Date,
        existingFileURL: URL
    ) -> [DevelopmentDemoFixture] {
        [
            fixture(
                id: "10000000-0000-4000-8000-000000000001",
                capturedAt: now,
                kind: .text,
                appName: "Notes",
                bundleID: "com.apple.Notes",
                type: "public.utf8-plain-text",
                data: Data(
                    """
                    ClipFlow visual acceptance
                    Review the selected item, source icon, and detail actions.
                    Long clipboard text stays inside a compact preview card.
                    Each additional line exercises the summary height limit.
                    Terminal output can contain many status messages.
                    Source paths may be long and deeply nested.
                    Error details remain selectable in the compact summary.
                    URLs and file paths use their own truncation behavior.
                    Images keep a bounded aspect-fit preview.
                    Mixed clipboard records combine a thumbnail and summary.
                    Metadata and actions remain visible below the preview.
                    The full preview button opens the complete local payload.
                    This final line verifies that overflow is truncated.
                    """.utf8
                )
            ),
            fixture(
                id: "10000000-0000-4000-8000-000000000002",
                capturedAt: now.addingTimeInterval(-60),
                kind: .richText,
                appName: "TextEdit",
                bundleID: "com.apple.TextEdit",
                type: "public.rtf",
                data: Data(
                    #"{\rtf1\ansi\deff0 {\fonttbl {\f0 Helvetica;}}\f0\fs28 ClipFlow \b rich text\b0\par Visual acceptance fixture}"#.utf8
                )
            ),
            fixture(
                id: "10000000-0000-4000-8000-000000000003",
                capturedAt: now.addingTimeInterval(-120),
                kind: .image,
                appName: "Preview",
                bundleID: "com.apple.Preview",
                type: "public.png",
                data: Data(base64Encoded:
                    "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"
                )!
            ),
            fixture(
                id: "10000000-0000-4000-8000-000000000004",
                capturedAt: now.addingTimeInterval(-180),
                kind: .file,
                appName: "Finder",
                bundleID: "com.apple.finder",
                representations: [
                    RawClipboardRepresentation(
                        type: "public.file-url",
                        data: existingFileURL.dataRepresentation
                    ),
                    RawClipboardRepresentation(
                        type: "public.utf8-plain-text",
                        data: Data(existingFileURL.path.utf8)
                    ),
                    RawClipboardRepresentation(
                        type: "com.apple.finder.node",
                        data: Data([1, 2, 3])
                    )
                ]
            ),
            fixture(
                id: "10000000-0000-4000-8000-000000000005",
                capturedAt: now.addingTimeInterval(-240),
                kind: .link,
                appName: "Safari",
                bundleID: "com.apple.Safari",
                representations: [
                    RawClipboardRepresentation(
                        type: "public.url",
                        data: Data("https://example.com/clipflow/visual-acceptance".utf8)
                    ),
                    RawClipboardRepresentation(
                        type: "public.utf8-plain-text",
                        data: Data("ClipFlow Visual Acceptance".utf8)
                    ),
                    RawClipboardRepresentation(
                        type: "org.chromium.source-url",
                        data: Data("https://example.com/clipflow/visual-acceptance".utf8)
                    )
                ]
            )
        ]
    }

    private static func fixture(
        id: String,
        capturedAt: Date,
        kind: ClipboardKind,
        appName: String,
        bundleID: String,
        type: String,
        data: Data
    ) -> DevelopmentDemoFixture {
        fixture(
            id: id,
            capturedAt: capturedAt,
            kind: kind,
            appName: appName,
            bundleID: bundleID,
            representations: [
                RawClipboardRepresentation(type: type, data: data)
            ]
        )
    }

    private static func fixture(
        id: String,
        capturedAt: Date,
        kind: ClipboardKind,
        appName: String,
        bundleID: String,
        representations: [RawClipboardRepresentation]
    ) -> DevelopmentDemoFixture {
        DevelopmentDemoFixture(
            id: UUID(uuidString: id)!,
            capturedAt: capturedAt,
            expectedKind: kind,
            capture: RawClipboardCapture(
                sourceAppName: appName,
                sourceBundleID: bundleID,
                items: [
                    RawClipboardItem(
                        representations: representations
                    )
                ]
            )
        )
    }
}
