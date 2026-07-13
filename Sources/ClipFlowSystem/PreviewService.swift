import AppKit
import ClipFlowCore
import Foundation
@preconcurrency import QuickLookUI
import UniformTypeIdentifiers

public struct PreviewArtifact: Equatable, Sendable {
    public let url: URL
    public let isTemporary: Bool
    fileprivate let temporaryDirectory: URL?

    fileprivate init(url: URL, isTemporary: Bool, temporaryDirectory: URL?) {
        self.url = url
        self.isTemporary = isTemporary
        self.temporaryDirectory = temporaryDirectory
    }
}

public enum PreviewServiceError: Error, Equatable, Sendable {
    case unsupportedPayload
    case invalidFileURL
}

public struct PreviewService: Sendable {
    private let root: URL

    public init(
        root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.clipflow.preview", isDirectory: true)
    ) {
        self.root = root
    }

    public func prepare(
        payloads: [NormalizedPayload],
        suggestedName: String
    ) throws -> PreviewArtifact {
        let fileManager = FileManager.default
        if let fileURL = Self.existingFileURL(in: payloads, fileManager: fileManager) {
            return PreviewArtifact(url: fileURL, isTemporary: false, temporaryDirectory: nil)
        }

        guard let payload = Self.preferredPayload(in: payloads) else {
            throw PreviewServiceError.unsupportedPayload
        }
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let fileName = Self.fileName(suggestedName, typeIdentifier: payload.type)
        let destination = directory.appendingPathComponent(fileName, isDirectory: false)
        try payload.data.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return PreviewArtifact(
            url: destination,
            isTemporary: true,
            temporaryDirectory: directory
        )
    }

    public func cleanup(_ artifact: PreviewArtifact) throws {
        let fileManager = FileManager.default
        guard artifact.isTemporary, let directory = artifact.temporaryDirectory else { return }
        let standardizedRoot = root.standardizedFileURL.path + "/"
        guard directory.standardizedFileURL.path.hasPrefix(standardizedRoot) else { return }
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    private static func existingFileURL(
        in payloads: [NormalizedPayload],
        fileManager: FileManager
    ) -> URL? {
        payloads.lazy
            .filter { $0.type == "public.file-url" }
            .compactMap { String(data: $0.data, encoding: .utf8) }
            .compactMap(URL.init(string:))
            .first { $0.isFileURL && fileManager.fileExists(atPath: $0.path) }
    }

    private static func preferredPayload(in payloads: [NormalizedPayload]) -> NormalizedPayload? {
        let order = [
            "public.png", "public.jpeg", "public.tiff", "public.webp",
            "com.compuserve.gif", "com.adobe.pdf", "public.rtf",
            "public.html", "public.utf8-plain-text", "public.plain-text"
        ]
        for type in order {
            if let payload = payloads.first(where: { $0.type == type }) { return payload }
        }
        return nil
    }

    static func fileName(_ suggestedName: String, typeIdentifier: String) -> String {
        let base = suggestedName
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ")).inverted)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeBase = base.isEmpty ? "ClipFlow Item" : String(base.prefix(80))
        guard let fileExtension = fileExtension(for: typeIdentifier),
              !fileExtension.isEmpty else {
            return safeBase
        }
        return "\(safeBase).\(fileExtension)"
    }

    private static func fileExtension(for typeIdentifier: String) -> String? {
        switch typeIdentifier {
        case "public.utf8-plain-text", "public.plain-text",
             "public.utf16-plain-text", "public.utf16-external-plain-text":
            "txt"
        case "public.rtf": "rtf"
        case "public.html": "html"
        case "public.url": "url"
        case "public.png": "png"
        case "public.jpeg": "jpg"
        case "public.tiff": "tiff"
        case "public.webp": "webp"
        case "com.compuserve.gif": "gif"
        case "com.adobe.pdf": "pdf"
        default: UTType(typeIdentifier)?.preferredFilenameExtension
        }
    }
}

@MainActor
public final class QuickLookPreviewController: NSObject,
    @preconcurrency QLPreviewPanelDataSource,
    @preconcurrency QLPreviewPanelDelegate {
    private let service: PreviewService
    private var artifact: PreviewArtifact?

    public init(service: PreviewService = PreviewService()) {
        self.service = service
    }

    public func show(payloads: [NormalizedPayload], suggestedName: String) throws {
        if let artifact { try? service.cleanup(artifact) }
        artifact = try service.prepare(payloads: payloads, suggestedName: suggestedName)
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        artifact == nil ? 0 : 1
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> any QLPreviewItem {
        artifact!.url as NSURL
    }

    public func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        if let artifact { try? service.cleanup(artifact) }
        artifact = nil
    }
}
