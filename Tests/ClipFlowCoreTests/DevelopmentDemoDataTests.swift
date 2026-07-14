import AppKit
import Foundation
import Testing
@testable import ClipFlowCore

@Suite("Development demo data")
struct DevelopmentDemoDataTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let existingFileURL = URL(fileURLWithPath: #filePath)

    @Test("covers every primary visual kind")
    func coversEveryPrimaryVisualKind() throws {
        let fixtures = DevelopmentDemoData.fixtures(
            now: now,
            existingFileURL: existingFileURL
        )
        let normalizer = ClipboardNormalizer(
            maxRepresentationBytes: 1_048_576,
            maxCaptureBytes: 5_242_880
        )

        #expect(fixtures.map(\.expectedKind) == [.text, .richText, .image, .file, .link])
        #expect(try fixtures.map { try normalizer.normalize($0.capture).kind }
            == fixtures.map(\.expectedKind))
    }

    @Test("is repeatable for fixed inputs")
    func fixedInputsAreRepeatable() {
        let first = DevelopmentDemoData.fixtures(
            now: now,
            existingFileURL: existingFileURL
        )
        let second = DevelopmentDemoData.fixtures(
            now: now,
            existingFileURL: existingFileURL
        )

        #expect(first == second)
        #expect(Set(first.map(\.id)).count == first.count)
        #expect(first.map(\.capturedAt) == [
            now,
            now.addingTimeInterval(-60),
            now.addingTimeInterval(-120),
            now.addingTimeInterval(-180),
            now.addingTimeInterval(-240)
        ])
    }

    @Test("uses the expected payload types and source applications")
    func payloadTypesAndSources() {
        let fixtures = DevelopmentDemoData.fixtures(
            now: now,
            existingFileURL: existingFileURL
        )

        #expect(fixtures.map { $0.capture.items.flatMap(\.representations).map(\.type) } == [
            ["public.utf8-plain-text"],
            ["public.rtf"],
            ["public.png"],
            ["public.file-url", "public.utf8-plain-text", "com.apple.finder.node"],
            ["public.url", "public.utf8-plain-text", "org.chromium.source-url"]
        ])
        #expect(fixtures.map { $0.capture.sourceBundleID } == [
            "com.apple.Notes",
            "com.apple.TextEdit",
            "com.apple.Preview",
            "com.apple.finder",
            "com.apple.Safari"
        ])
        #expect(fixtures.map { $0.capture.sourceAppName } == [
            "Notes", "TextEdit", "Preview", "Finder", "Safari"
        ])
    }

    @Test("preserves rich fixture contents")
    func richFixtureContents() throws {
        let fixtures = DevelopmentDemoData.fixtures(
            now: now,
            existingFileURL: existingFileURL
        )

        let text = try #require(String(
            data: fixtures[0].capture.items[0].representations[0].data,
            encoding: .utf8
        ))
        let fileURL = try #require(URL(
            dataRepresentation: fixtures[3].capture.items[0].representations[0].data,
            relativeTo: nil
        ))
        let link = try #require(String(
            data: fixtures[4].capture.items[0].representations[0].data,
            encoding: .utf8
        ))
        let filePathRepresentation = try #require(
            fixtures[3].capture.items[0].representations.first {
                $0.type == "public.utf8-plain-text"
            }
        )
        let linkTitleRepresentation = try #require(
            fixtures[4].capture.items[0].representations.first {
                $0.type == "public.utf8-plain-text"
            }
        )
        let filePath = try #require(String(
            data: filePathRepresentation.data,
            encoding: .utf8
        ))
        let linkTitle = try #require(String(
            data: linkTitleRepresentation.data,
            encoding: .utf8
        ))

        #expect(text.contains("\n"))
        #expect(fileURL == existingFileURL)
        #expect(filePath == existingFileURL.path)
        #expect(link.hasPrefix("https://"))
        #expect(linkTitle == "ClipFlow Visual Acceptance")
    }

    @Test("image fixture decodes as a recognizable non-square PNG")
    func imageFixtureDecodesAtExpectedSize() throws {
        let fixtures = DevelopmentDemoData.fixtures(
            now: now,
            existingFileURL: existingFileURL
        )
        let pngData = fixtures[2].capture.items[0].representations[0].data
        let bitmap = try #require(NSBitmapImageRep(data: pngData))
        let topLeft = try #require(bitmap.colorAt(x: 8, y: 8)?.usingColorSpace(.deviceRGB))
        let bottomRight = try #require(bitmap.colorAt(x: 87, y: 55)?.usingColorSpace(.deviceRGB))

        #expect(bitmap.pixelsWide == 96)
        #expect(bitmap.pixelsHigh == 64)
        #expect(topLeft.redComponent > 0.8)
        #expect(topLeft.greenComponent < 0.3)
        #expect(bottomRight.blueComponent > 0.8)
        #expect(bottomRight.redComponent < 0.3)
    }

    @Test("RTF fixture parses to expected styled text")
    func richTextFixtureParses() throws {
        let fixtures = DevelopmentDemoData.fixtures(
            now: now,
            existingFileURL: existingFileURL
        )
        let rtfData = fixtures[1].capture.items[0].representations[0].data
        let attributed = try NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        let boldRange = (attributed.string as NSString).range(of: "rich text")
        let font = try #require(attributed.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont)

        #expect(attributed.string == "ClipFlow rich text\nVisual acceptance fixture")
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }
}
