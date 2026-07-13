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

    @Test("cancelling PDF generation cancels Quick Look and removes its temporary file")
    func cancellingPDFGenerationCancelsQuickLookAndCleansUp() async throws {
        let generator = FakeQuickLookThumbnailGenerator()
        let service = ClipboardThumbnailService(quickLookGenerator: generator)
        let task = Task {
            await service.pdfThumbnail(
                data: Data("%PDF-1.7".utf8),
                maximumPixelSize: 64
            )
        }

        let request = await generator.waitForGeneratedRequest()
        #expect(FileManager.default.fileExists(atPath: request.fileURL.path))

        task.cancel()
        let thumbnail = await task.value

        #expect(thumbnail == nil)
        #expect(generator.cancelledRequestIDs == [request.id])
        #expect(!FileManager.default.fileExists(atPath: request.fileURL.path))

        generator.complete(
            request,
            with: GeneratedThumbnail(
                imageData: Data([1]),
                pixelWidth: 1,
                pixelHeight: 1
            )
        )
        #expect(!FileManager.default.fileExists(atPath: request.fileURL.path))
    }
}

private final class FakeQuickLookThumbnailGenerator:
    QuickLookThumbnailGenerating,
    @unchecked Sendable {
    private let lock = NSLock()
    private var generatedRequests: [QuickLookThumbnailRequest] = []
    private var cancelledIDs: [UUID] = []
    private var completions: [UUID: @Sendable (GeneratedThumbnail?) -> Void] = [:]
    private var requestWaiter: CheckedContinuation<QuickLookThumbnailRequest, Never>?

    var cancelledRequestIDs: [UUID] {
        lock.withLock { cancelledIDs }
    }

    func makeRequest(
        fileURL: URL,
        maximumPixelSize: Int
    ) -> QuickLookThumbnailRequest {
        QuickLookThumbnailRequest(fileURL: fileURL)
    }

    func generate(
        _ request: QuickLookThumbnailRequest,
        completion: @escaping @Sendable (GeneratedThumbnail?) -> Void
    ) {
        let waiter = lock.withLock { () -> CheckedContinuation<QuickLookThumbnailRequest, Never>? in
            generatedRequests.append(request)
            completions[request.id] = completion
            defer { requestWaiter = nil }
            return requestWaiter
        }
        waiter?.resume(returning: request)
    }

    func cancel(_ request: QuickLookThumbnailRequest) {
        lock.withLock { cancelledIDs.append(request.id) }
    }

    func complete(
        _ request: QuickLookThumbnailRequest,
        with thumbnail: GeneratedThumbnail?
    ) {
        let completion = lock.withLock { completions.removeValue(forKey: request.id) }
        completion?(thumbnail)
    }

    func waitForGeneratedRequest() async -> QuickLookThumbnailRequest {
        return await withCheckedContinuation { continuation in
            let request = lock.withLock { () -> QuickLookThumbnailRequest? in
                if let request = generatedRequests.first {
                    return request
                }
                requestWaiter = continuation
                return nil
            }
            request.map { continuation.resume(returning: $0) }
        }
    }
}
