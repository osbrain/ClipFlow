import CryptoKit
import Foundation

public struct RawClipboardRepresentation: Equatable, Sendable {
    public let type: String
    public let data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

public struct RawClipboardItem: Equatable, Sendable {
    public let representations: [RawClipboardRepresentation]

    public init(representations: [RawClipboardRepresentation]) {
        self.representations = representations
    }
}

public struct RawClipboardCapture: Equatable, Sendable {
    public let sourceAppName: String
    public let sourceBundleID: String?
    public let items: [RawClipboardItem]

    public init(
        sourceAppName: String,
        sourceBundleID: String?,
        items: [RawClipboardItem]
    ) {
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.items = items
    }
}

public struct NormalizedPayload: Equatable, Sendable {
    public let itemIndex: Int
    public let type: String
    public let data: Data

    public init(itemIndex: Int, type: String, data: Data) {
        self.itemIndex = itemIndex
        self.type = type
        self.data = data
    }
}

public struct NormalizedCapture: Equatable, Sendable {
    public let sourceAppName: String
    public let sourceBundleID: String?
    public let kind: ClipboardKind
    public let previewText: String
    public let searchText: String
    public let byteSize: Int
    public let contentHash: String
    public let payloads: [NormalizedPayload]

    public init(
        sourceAppName: String,
        sourceBundleID: String?,
        kind: ClipboardKind,
        previewText: String,
        searchText: String,
        byteSize: Int,
        contentHash: String,
        payloads: [NormalizedPayload]
    ) {
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.kind = kind
        self.previewText = previewText
        self.searchText = searchText
        self.byteSize = byteSize
        self.contentHash = contentHash
        self.payloads = payloads
    }
}

public enum ClipboardNormalizationError: Error, Equatable, Sendable {
    case invalidLimits
    case noUsablePayload
}

public struct ClipboardNormalizer: Sendable {
    private let maxRepresentationBytes: Int
    private let maxCaptureBytes: Int

    public init(maxRepresentationBytes: Int, maxCaptureBytes: Int) {
        self.maxRepresentationBytes = maxRepresentationBytes
        self.maxCaptureBytes = maxCaptureBytes
    }

    public func normalize(_ capture: RawClipboardCapture) throws -> NormalizedCapture {
        guard maxRepresentationBytes > 0, maxCaptureBytes > 0 else {
            throw ClipboardNormalizationError.invalidLimits
        }

        var accepted: [NormalizedPayload] = []
        var totalBytes = 0

        for (itemIndex, item) in capture.items.enumerated() {
            for representation in item.representations {
                let size = representation.data.count
                guard size <= maxRepresentationBytes else { continue }
                guard totalBytes <= maxCaptureBytes - size else { continue }

                accepted.append(
                    NormalizedPayload(
                        itemIndex: itemIndex,
                        type: representation.type,
                        data: representation.data
                    )
                )
                totalBytes += size
            }
        }

        guard !accepted.isEmpty else {
            throw ClipboardNormalizationError.noUsablePayload
        }

        let preview = Self.previewText(for: accepted)
        let kind = Self.aggregateKind(for: accepted)

        return NormalizedCapture(
            sourceAppName: capture.sourceAppName,
            sourceBundleID: capture.sourceBundleID,
            kind: kind,
            previewText: preview,
            searchText: preview.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            ),
            byteSize: totalBytes,
            contentHash: Self.contentHash(for: accepted),
            payloads: accepted
        )
    }

    private static func previewText(for payloads: [NormalizedPayload]) -> String {
        let preferredTypes = [
            "public.utf8-plain-text",
            "public.plain-text",
            "public.url",
            "public.file-url"
        ]

        for type in preferredTypes {
            if let payload = payloads.first(where: { $0.type == type }),
               let value = String(data: payload.data, encoding: .utf8) {
                return normalizeLineEndings(value)
            }
        }

        return payloads.first.map { "\($0.type) · \($0.data.count) bytes" } ?? ""
    }

    private static func normalizeLineEndings(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func aggregateKind(for payloads: [NormalizedPayload]) -> ClipboardKind {
        let kinds = Set(payloads.map { kind(for: $0.type) })
        return kinds.count == 1 ? kinds.first! : .mixed
    }

    private static func kind(for type: String) -> ClipboardKind {
        switch type {
        case "public.utf8-plain-text", "public.plain-text":
            return .text
        case "public.rtf", "public.html":
            return .richText
        case "public.url":
            return .link
        case "public.file-url":
            return .file
        case "public.png", "public.tiff", "public.jpeg", "public.webp", "com.adobe.pdf":
            return .image
        default:
            return .unknown
        }
    }

    private static func contentHash(for payloads: [NormalizedPayload]) -> String {
        var hasher = SHA256()

        for payload in payloads {
            update(&hasher, integer: payload.itemIndex)
            update(&hasher, data: Data(payload.type.utf8))
            update(&hasher, data: payload.data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func update(_ hasher: inout SHA256, integer: Int) {
        var value = UInt64(integer).bigEndian
        withUnsafeBytes(of: &value) { bytes in
            hasher.update(bufferPointer: bytes)
        }
    }

    private static func update(_ hasher: inout SHA256, data: Data) {
        update(&hasher, integer: data.count)
        hasher.update(data: data)
    }
}
