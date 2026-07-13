import Foundation
import Testing
@testable import ClipFlowSystem

@Suite("Clipboard thumbnail service")
struct ClipboardThumbnailServiceTests {
    private let onePixelPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!

    @Test("creates a bounded PNG thumbnail")
    func createsBoundedThumbnail() throws {
        let thumbnail = try #require(
            ClipboardThumbnailService().imageThumbnail(
                data: onePixelPNG,
                maximumPixelSize: 64
            )
        )

        #expect(thumbnail.pixelWidth <= 64)
        #expect(thumbnail.pixelHeight <= 64)
        #expect(!thumbnail.imageData.isEmpty)
    }

    @Test("rejects corrupt image data")
    func rejectsCorruptImageData() {
        let thumbnail = ClipboardThumbnailService().imageThumbnail(
            data: Data([0, 1, 2]),
            maximumPixelSize: 64
        )

        #expect(thumbnail == nil)
    }
}
