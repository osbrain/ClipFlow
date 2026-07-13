import AppKit
import ClipFlowCore
import ClipFlowStorage
import ClipFlowSystem
import ClipFlowUI
import Foundation
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
           let thumbnail = await thumbnailService.pdfThumbnail(
               data: pdf.data,
               maximumPixelSize: maximumPixelSize
           ) {
            return .pngData(thumbnail.imageData)
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

}
