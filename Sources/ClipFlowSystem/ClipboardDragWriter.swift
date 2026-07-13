import ClipFlowCore
import Foundation
import UniformTypeIdentifiers

public enum ClipboardDragRepresentation: Equatable, Sendable {
    case fileURL(URL)
    case promisedFile(fileName: String, typeIdentifier: String, data: Data)
}

public enum ClipboardDragError: Error, Equatable, Sendable {
    case unsupportedPayload
    case providerCreationFailed
}

public struct ClipboardDragWriter: Sendable {
    private let root: URL

    public init(
        root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.clipflow.drag", isDirectory: true)
    ) {
        self.root = root
    }

    public func representation(
        for payloads: [NormalizedPayload],
        suggestedName: String
    ) throws -> ClipboardDragRepresentation {
        let fileManager = FileManager.default
        if let fileURL = payloads.lazy
            .filter({ $0.type == "public.file-url" })
            .compactMap({ String(data: $0.data, encoding: .utf8) })
            .compactMap(URL.init(string:))
            .first(where: { $0.isFileURL && fileManager.fileExists(atPath: $0.path) }) {
            return .fileURL(fileURL)
        }

        let order = [
            "public.png", "public.jpeg", "public.tiff", "public.webp",
            "com.compuserve.gif", "com.adobe.pdf", "public.rtf", "public.html",
            "public.utf8-plain-text", "public.plain-text", "public.url"
        ]
        guard let payload = order.lazy.compactMap({ type in
            payloads.first(where: { $0.type == type })
        }).first else {
            throw ClipboardDragError.unsupportedPayload
        }
        return .promisedFile(
            fileName: PreviewService.fileName(suggestedName, typeIdentifier: payload.type),
            typeIdentifier: payload.type,
            data: payload.data
        )
    }

    @MainActor
    public func itemProvider(
        for payloads: [NormalizedPayload],
        suggestedName: String
    ) throws -> NSItemProvider {
        switch try representation(for: payloads, suggestedName: suggestedName) {
        case .fileURL(let url):
            guard let provider = NSItemProvider(contentsOf: url) else {
                throw ClipboardDragError.providerCreationFailed
            }
            return provider

        case .promisedFile(let fileName, let typeIdentifier, let data):
            let provider = NSItemProvider()
            provider.suggestedName = fileName
            provider.registerFileRepresentation(
                forTypeIdentifier: typeIdentifier,
                fileOptions: [],
                visibility: .all
            ) { completion in
                let progress = Progress(totalUnitCount: 1)
                do {
                    let fileManager = FileManager.default
                    try fileManager.createDirectory(
                        at: root,
                        withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700]
                    )
                    let destination = root
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                        .appendingPathComponent(fileName, isDirectory: false)
                    try fileManager.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700]
                    )
                    try data.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
                    try fileManager.setAttributes(
                        [.posixPermissions: 0o600],
                        ofItemAtPath: destination.path
                    )
                    progress.completedUnitCount = 1
                    completion(destination, false, nil)
                } catch {
                    completion(nil, false, error)
                }
                return progress
            }
            return provider
        }
    }
}
