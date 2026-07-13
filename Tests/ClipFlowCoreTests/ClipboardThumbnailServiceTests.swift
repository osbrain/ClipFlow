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

    @Test("cancelling before Quick Look submission does not generate or cancel a request")
    func cancellingBeforeSubmissionSkipsQuickLook() async throws {
        let makeRequestGate = BlockingGate()
        let generator = FakeQuickLookThumbnailGenerator(
            makeRequestGate: makeRequestGate
        )
        let service = ClipboardThumbnailService(quickLookGenerator: generator)
        let task = Task {
            await service.pdfThumbnail(
                data: Data("%PDF-1.7".utf8),
                maximumPixelSize: 64
            )
        }

        await makeRequestGate.waitUntilEntered()
        let request = try #require(generator.firstCreatedRequest)
        #expect(FileManager.default.fileExists(atPath: request.fileURL.path))

        task.cancel()
        makeRequestGate.release()
        let thumbnail = await task.value

        #expect(thumbnail == nil)
        #expect(generator.generatedRequestIDs.isEmpty)
        #expect(generator.cancelledRequestIDs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: request.fileURL.path))
    }

    @Test("cancelling after Quick Look submission cancels the request exactly once")
    func cancellingAfterSubmissionCancelsExactlyOnce() async throws {
        let generateGate = BlockingGate()
        let generator = FakeQuickLookThumbnailGenerator(generateGate: generateGate)
        let service = ClipboardThumbnailService(quickLookGenerator: generator)
        let task = Task {
            await service.pdfThumbnail(
                data: Data("%PDF-1.7".utf8),
                maximumPixelSize: 64
            )
        }

        await generateGate.waitUntilEntered()
        let request = try #require(generator.firstCreatedRequest)
        #expect(FileManager.default.fileExists(atPath: request.fileURL.path))

        task.cancel()
        generateGate.release()
        let thumbnail = await task.value

        #expect(thumbnail == nil)
        #expect(generator.generatedRequestIDs == [request.id])
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
    private let makeRequestGate: BlockingGate?
    private let generateGate: BlockingGate?
    private var createdRequests: [QuickLookThumbnailRequest] = []
    private var generatedRequests: [QuickLookThumbnailRequest] = []
    private var cancelledIDs: [UUID] = []
    private var completions: [UUID: @Sendable (GeneratedThumbnail?) -> Void] = [:]

    init(
        makeRequestGate: BlockingGate? = nil,
        generateGate: BlockingGate? = nil
    ) {
        self.makeRequestGate = makeRequestGate
        self.generateGate = generateGate
    }

    var firstCreatedRequest: QuickLookThumbnailRequest? {
        lock.withLock { createdRequests.first }
    }

    var generatedRequestIDs: [UUID] {
        lock.withLock { generatedRequests.map(\.id) }
    }

    var cancelledRequestIDs: [UUID] {
        lock.withLock { cancelledIDs }
    }

    func makeRequest(
        fileURL: URL,
        maximumPixelSize: Int
    ) -> QuickLookThumbnailRequest {
        let request = QuickLookThumbnailRequest(fileURL: fileURL)
        lock.withLock { createdRequests.append(request) }
        makeRequestGate?.enterAndWait()
        return request
    }

    func generate(
        _ request: QuickLookThumbnailRequest,
        completion: @escaping @Sendable (GeneratedThumbnail?) -> Void
    ) {
        lock.withLock {
            generatedRequests.append(request)
            completions[request.id] = completion
        }
        generateGate?.enterAndWait()
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

}

private final class BlockingGate: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?

    func enterAndWait() {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            entered = true
            defer { enteredWaiter = nil }
            return enteredWaiter
        }
        waiter?.resume()
        releaseSemaphore.wait()
    }

    func waitUntilEntered() async {
        await withCheckedContinuation { continuation in
            let isEntered = lock.withLock {
                if entered { return true }
                enteredWaiter = continuation
                return false
            }
            if isEntered {
                continuation.resume()
            }
        }
    }

    func release() {
        releaseSemaphore.signal()
    }
}
