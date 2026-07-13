import AppKit
import ClipFlowCore
import ClipFlowStorage
import ClipFlowSystem
import ClipFlowUI
import Foundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

@MainActor
public final class AppClipboardVisualService: ClipboardVisualServing {
    private enum LoadedVisual: Sendable {
        case pngData(Data)
        case fileURL(URL)
    }

    private let repository: ClipboardRepository
    private let applicationIconProvider: ApplicationIconProvider
    private let thumbnailService: ClipboardThumbnailService
    private let cache = NSCache<NSString, NSImage>()

    public init(
        repository: ClipboardRepository,
        applicationIconProvider: ApplicationIconProvider = ApplicationIconProvider(),
        thumbnailService: ClipboardThumbnailService = ClipboardThumbnailService()
    ) {
        self.repository = repository
        self.applicationIconProvider = applicationIconProvider
        self.thumbnailService = thumbnailService
    }

    public func metadataVisual(for item: ClipboardItem) -> ClipboardVisualDescriptor {
        ClipboardVisualDescriptor(
            itemID: item.id,
            applicationIcon: applicationIconProvider.icon(
                for: ApplicationIconLookup(
                    bundleID: item.bundleID,
                    appName: item.appName
                )
            ),
            thumbnail: nil,
            kind: item.kind.presentation
        )
    }

    public func loadThumbnail(
        for item: ClipboardItem,
        maximumPixelSize: Int
    ) async -> NSImage? {
        guard maximumPixelSize > 0 else { return nil }
        let cacheKey = "\(item.id):\(item.contentHash):\(maximumPixelSize)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let repository = repository
        let thumbnailService = thumbnailService
        let worker = Task.detached(priority: .utility) {
            await Self.loadVisual(
                itemID: item.id,
                maximumPixelSize: maximumPixelSize,
                repository: repository,
                thumbnailService: thumbnailService
            )
        }
        let loaded = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled, let loaded else { return nil }

        let image: NSImage?
        switch loaded {
        case .pngData(let data):
            image = NSImage(data: data)
        case .fileURL(let url):
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        if let image {
            cache.setObject(image, forKey: cacheKey)
        }
        return image
    }

    private nonisolated static func loadVisual(
        itemID: UUID,
        maximumPixelSize: Int,
        repository: ClipboardRepository,
        thumbnailService: ClipboardThumbnailService
    ) async -> LoadedVisual? {
        guard !Task.isCancelled else { return nil }
        let payloads: [RepositoryPayload]
        do {
            payloads = try repository.payloads(for: itemID)
        } catch {
            return nil
        }
        guard !Task.isCancelled else { return nil }

        if let imagePayload = preferredImagePayload(in: payloads),
           let thumbnail = thumbnailService.imageThumbnail(
               data: imagePayload.data,
               maximumPixelSize: maximumPixelSize
           ) {
            return .pngData(thumbnail.imageData)
        }

        if let pdf = payloads.first(where: { $0.type == UTType.pdf.identifier }),
           let data = await pdfThumbnail(
               data: pdf.data,
               maximumPixelSize: maximumPixelSize
           ) {
            return .pngData(data)
        }

        if let url = existingFileURL(in: payloads) {
            return .fileURL(url)
        }
        return nil
    }

    private nonisolated static func preferredImagePayload(
        in payloads: [RepositoryPayload]
    ) -> RepositoryPayload? {
        let preferredTypes = [
            UTType.png.identifier,
            UTType.jpeg.identifier,
            UTType.tiff.identifier,
            "public.webp",
            UTType.gif.identifier
        ]
        for type in preferredTypes {
            if let payload = payloads.first(where: { $0.type == type }) {
                return payload
            }
        }
        return payloads.first {
            $0.type != UTType.pdf.identifier
                && UTType($0.type)?.conforms(to: .image) == true
        }
    }

    private nonisolated static func existingFileURL(
        in payloads: [RepositoryPayload]
    ) -> URL? {
        payloads.lazy
            .filter { $0.type == UTType.fileURL.identifier }
            .compactMap { String(data: $0.data, encoding: .utf8) }
            .compactMap(URL.init(string:))
            .first {
                $0.isFileURL && FileManager.default.fileExists(atPath: $0.path)
            }
    }

    private nonisolated static func pdfThumbnail(
        data: Data,
        maximumPixelSize: Int
    ) async -> Data? {
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
            try data.write(to: fileURL, options: [.atomic])
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

        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: maximumPixelSize, height: maximumPixelSize),
            scale: 1,
            representationTypes: .thumbnail
        )
        do {
            let representation = try await QLThumbnailGenerator.shared
                .generateBestRepresentation(for: request)
            guard !Task.isCancelled else { return nil }
            return pngData(for: representation.cgImage)
        } catch {
            return nil
        }
    }

    private nonisolated static func pngData(for image: CGImage) -> Data? {
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
        return output as Data
    }
}
