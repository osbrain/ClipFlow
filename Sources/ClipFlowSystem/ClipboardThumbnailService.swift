import Foundation
import ImageIO
@preconcurrency import QuickLookThumbnailing
import UniformTypeIdentifiers

public struct GeneratedThumbnail: Equatable, Sendable {
    public let imageData: Data
    public let pixelWidth: Int
    public let pixelHeight: Int

}

public struct ClipboardThumbnailService: Sendable {
    private let quickLookGenerator: any QuickLookThumbnailGenerating

    public init() {
        quickLookGenerator = SystemQuickLookThumbnailGenerator()
    }

    init(quickLookGenerator: any QuickLookThumbnailGenerating) {
        self.quickLookGenerator = quickLookGenerator
    }

    public func imageThumbnail(
        data: Data,
        maximumPixelSize: Int
    ) -> GeneratedThumbnail? {
        guard maximumPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }

        return generatedThumbnail(from: image)
    }

    public func pdfThumbnail(
        data: Data,
        maximumPixelSize: Int
    ) async -> GeneratedThumbnail? {
        guard maximumPixelSize > 0 else { return nil }
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("com.clipflow.thumbnail", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("document.pdf")

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(
                to: fileURL,
                options: [.atomic, .completeFileProtectionUnlessOpen]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            try? fileManager.removeItem(at: directory)
            return nil
        }
        defer { try? fileManager.removeItem(at: directory) }
        guard !Task.isCancelled else { return nil }

        let generator = quickLookGenerator
        let request = generator.makeRequest(
            fileURL: fileURL,
            maximumPixelSize: maximumPixelSize
        )
        let state = QuickLookContinuationState()
        let thumbnail = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard state.beginSubmission(with: continuation) else {
                    continuation.resume(returning: nil)
                    return
                }
                generator.generate(request) { thumbnail in
                    state.complete(with: thumbnail)
                }
                let action = state.finishSubmission()
                if action.shouldCancelRequest {
                    generator.cancel(request)
                }
                action.continuation?.resume(returning: nil)
            }
        } onCancel: {
            let action = state.cancel()
            if action.shouldCancelRequest {
                generator.cancel(request)
            }
            action.continuation?.resume(returning: nil)
        }
        guard !Task.isCancelled else { return nil }
        return thumbnail
    }
}

struct QuickLookThumbnailRequest: @unchecked Sendable {
    let id: UUID
    let fileURL: URL
    fileprivate let platformRequest: QLThumbnailGenerator.Request?

    init(fileURL: URL) {
        id = UUID()
        self.fileURL = fileURL
        platformRequest = nil
    }

    fileprivate init(
        fileURL: URL,
        platformRequest: QLThumbnailGenerator.Request
    ) {
        id = UUID()
        self.fileURL = fileURL
        self.platformRequest = platformRequest
    }
}

protocol QuickLookThumbnailGenerating: Sendable {
    func makeRequest(
        fileURL: URL,
        maximumPixelSize: Int
    ) -> QuickLookThumbnailRequest
    func generate(
        _ request: QuickLookThumbnailRequest,
        completion: @escaping @Sendable (GeneratedThumbnail?) -> Void
    )
    func cancel(_ request: QuickLookThumbnailRequest)
}

private final class SystemQuickLookThumbnailGenerator:
    QuickLookThumbnailGenerating,
    @unchecked Sendable {
    private let generator = QLThumbnailGenerator.shared

    func makeRequest(
        fileURL: URL,
        maximumPixelSize: Int
    ) -> QuickLookThumbnailRequest {
        QuickLookThumbnailRequest(
            fileURL: fileURL,
            platformRequest: QLThumbnailGenerator.Request(
                fileAt: fileURL,
                size: CGSize(
                    width: maximumPixelSize,
                    height: maximumPixelSize
                ),
                scale: 1,
                representationTypes: .thumbnail
            )
        )
    }

    func generate(
        _ request: QuickLookThumbnailRequest,
        completion: @escaping @Sendable (GeneratedThumbnail?) -> Void
    ) {
        guard let platformRequest = request.platformRequest else {
            completion(nil)
            return
        }
        generator.generateBestRepresentation(for: platformRequest) { representation, _ in
            completion(representation.flatMap { generatedThumbnail(from: $0.cgImage) })
        }
    }

    func cancel(_ request: QuickLookThumbnailRequest) {
        guard let platformRequest = request.platformRequest else { return }
        generator.cancel(platformRequest)
    }
}

private final class QuickLookContinuationState: @unchecked Sendable {
    private enum Phase {
        case ready
        case submitting
        case submitted
        case finished
    }

    private let lock = NSLock()
    private var continuation: CheckedContinuation<GeneratedThumbnail?, Never>?
    private var phase = Phase.ready
    private var cancellationRequested = false

    func beginSubmission(
        with continuation: CheckedContinuation<GeneratedThumbnail?, Never>
    ) -> Bool {
        lock.withLock {
            guard phase == .ready else { return false }
            phase = .submitting
            self.continuation = continuation
            return true
        }
    }

    func finishSubmission() -> QuickLookCancellationAction {
        lock.withLock {
            guard phase == .submitting else { return .none }
            if cancellationRequested {
                phase = .finished
                let continuation = self.continuation
                self.continuation = nil
                return QuickLookCancellationAction(
                    shouldCancelRequest: true,
                    continuation: continuation
                )
            }
            phase = .submitted
            return .none
        }
    }

    func complete(with thumbnail: GeneratedThumbnail?) {
        let continuation: CheckedContinuation<GeneratedThumbnail?, Never>? = lock.withLock {
            guard !cancellationRequested,
                  phase == .submitting || phase == .submitted else {
                return nil
            }
            phase = .finished
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: thumbnail)
    }

    func cancel() -> QuickLookCancellationAction {
        lock.withLock {
            switch phase {
            case .ready:
                phase = .finished
                cancellationRequested = true
                return .none

            case .submitting:
                cancellationRequested = true
                return .none

            case .submitted:
                phase = .finished
                cancellationRequested = true
                let continuation = self.continuation
                self.continuation = nil
                return QuickLookCancellationAction(
                    shouldCancelRequest: true,
                    continuation: continuation
                )

            case .finished:
                return .none
            }
        }
    }
}

private struct QuickLookCancellationAction {
    static let none = Self(shouldCancelRequest: false, continuation: nil)

    let shouldCancelRequest: Bool
    let continuation: CheckedContinuation<GeneratedThumbnail?, Never>?
}

private func generatedThumbnail(from image: CGImage) -> GeneratedThumbnail? {
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        output,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return GeneratedThumbnail(
        imageData: output as Data,
        pixelWidth: image.width,
        pixelHeight: image.height
    )
}
