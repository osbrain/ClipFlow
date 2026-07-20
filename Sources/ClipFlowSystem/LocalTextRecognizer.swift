import AppKit
import ClipFlowCore
import Foundation
import Vision

public protocol LocalTextRecognizing: Sendable {
    func recognizeText(in capture: NormalizedCapture) async throws -> String?
}

public final class VisionTextRecognizer: LocalTextRecognizing, @unchecked Sendable {
    public init() {}

    public func recognizeText(in capture: NormalizedCapture) async throws -> String? {
        guard capture.kind == .image,
              let image = image(from: capture.payloads),
              let cgImage = image.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
              ) else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func image(from payloads: [NormalizedPayload]) -> NSImage? {
        let supportedTypes = ["public.png", "public.jpeg", "public.tiff", "public.heic"]
        for type in supportedTypes {
            if let data = payloads.first(where: { $0.type == type })?.data,
               let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }
}
