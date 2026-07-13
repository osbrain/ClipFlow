import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct GeneratedThumbnail: Equatable, Sendable {
    public let imageData: Data
    public let pixelWidth: Int
    public let pixelHeight: Int

}

public struct ClipboardThumbnailService: Sendable {
    public init() {}

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
}
