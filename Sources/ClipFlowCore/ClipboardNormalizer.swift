import CryptoKit
import Foundation
import UniformTypeIdentifiers

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
            contentHash: Self.semanticContentHash(for: accepted),
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
        let itemKinds = Dictionary(grouping: payloads, by: \.itemIndex)
            .sorted { $0.key < $1.key }
            .map { semanticKind(for: $0.value) }
        let kinds = Set(itemKinds)
        return kinds.count == 1 ? kinds.first ?? .unknown : .mixed
    }

    private static func semanticKind(for payloads: [NormalizedPayload]) -> ClipboardKind {
        if payloads.contains(where: isFileRepresentation) { return .file }
        if payloads.contains(where: isURLRepresentation) { return .link }
        if payloads.contains(where: isImageRepresentation) { return .image }
        if payloads.contains(where: isRichTextRepresentation) { return .richText }

        guard let text = decodedPlainText(in: payloads) else { return .unknown }
        if inferredFileURL(from: text) != nil { return .file }
        if inferredWebURL(from: text) != nil { return .link }
        return .text
    }

    private static func isFileRepresentation(_ payload: NormalizedPayload) -> Bool {
        if [
            "public.file-url",
            "NSFilenamesPboardType",
            "com.apple.pasteboard.promised-file-url"
        ].contains(payload.type) {
            return true
        }
        return UTType(payload.type)?.conforms(to: .fileURL) == true
    }

    private static func isURLRepresentation(_ payload: NormalizedPayload) -> Bool {
        guard !isFileRepresentation(payload) else { return false }
        if payload.type == "public.url" { return true }
        return UTType(payload.type)?.conforms(to: .url) == true
    }

    private static func isImageRepresentation(_ payload: NormalizedPayload) -> Bool {
        if ["com.adobe.pdf", "com.compuserve.gif"].contains(payload.type) {
            return true
        }
        guard let type = UTType(payload.type) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    private static func isRichTextRepresentation(_ payload: NormalizedPayload) -> Bool {
        if ["public.rtf", "public.rtfd", "public.html"].contains(payload.type) {
            return true
        }
        guard let type = UTType(payload.type) else { return false }
        return type.conforms(to: .rtf) || type.conforms(to: .html)
    }

    private static func decodedPlainText(in payloads: [NormalizedPayload]) -> String? {
        let preferredTypes = [
            "public.utf8-plain-text",
            "public.plain-text",
            "public.utf16-plain-text",
            "public.utf16-external-plain-text"
        ]
        let candidates = preferredTypes.compactMap { preferred in
            payloads.first { $0.type == preferred }
        } + payloads.filter { payload in
            UTType(payload.type)?.conforms(to: .plainText) == true &&
                !preferredTypes.contains(payload.type)
        }

        for payload in candidates {
            if let value = String(data: payload.data, encoding: .utf8)
                ?? String(data: payload.data, encoding: .utf16) {
                return normalizeLineEndings(value)
            }
        }
        return nil
    }

    private static func inferredWebURL(from text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains(where: \.isWhitespace),
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else {
            return nil
        }
        return url
    }

    private static func inferredFileURL(from text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains(where: \.isWhitespace),
              let url = URL(string: value),
              url.isFileURL else {
            return nil
        }
        return url
    }

    private static func semanticContentHash(for payloads: [NormalizedPayload]) -> String {
        var hasher = SHA256()
        update(&hasher, data: Data("clipflow-semantic-v1".utf8))

        for (itemIndex, itemPayloads) in Dictionary(grouping: payloads, by: \.itemIndex)
            .sorted(by: { $0.key < $1.key }) {
            let kind = semanticKind(for: itemPayloads)
            update(&hasher, integer: itemIndex)
            update(&hasher, data: Data(semanticDomain(for: kind).utf8))
            update(&hasher, data: semanticIdentity(for: itemPayloads, kind: kind))
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func semanticDomain(for kind: ClipboardKind) -> String {
        switch kind {
        case .text, .richText:
            "text"
        default:
            kind.rawValue
        }
    }

    private static func semanticIdentity(
        for payloads: [NormalizedPayload],
        kind: ClipboardKind
    ) -> Data {
        switch kind {
        case .text, .richText:
            if let text = decodedPlainText(in: payloads) {
                return Data(normalizeLineEndings(text).utf8)
            }
        case .link:
            if let url = representedURL(in: payloads, fileURL: false)
                ?? decodedPlainText(in: payloads).flatMap(inferredWebURL(from:)) {
                return Data(canonicalWebURL(url).utf8)
            }
        case .file:
            if let url = representedURL(in: payloads, fileURL: true)
                ?? decodedPlainText(in: payloads).flatMap(inferredFileURL(from:)) {
                return Data(url.standardizedFileURL.absoluteString.utf8)
            }
        case .image:
            if let payload = preferredBinaryPayload(in: payloads) {
                var identity = Data(payload.type.utf8)
                identity.append(0)
                identity.append(payload.data)
                return identity
            }
        case .mixed, .unknown:
            break
        }

        return fullPayloadIdentity(payloads)
    }

    private static func representedURL(
        in payloads: [NormalizedPayload],
        fileURL: Bool
    ) -> URL? {
        let candidates = payloads.filter { payload in
            fileURL ? isFileRepresentation(payload) : isURLRepresentation(payload)
        }.sorted { $0.type < $1.type }

        for payload in candidates {
            if let url = URL(dataRepresentation: payload.data, relativeTo: nil),
               url.isFileURL == fileURL {
                return url
            }
            if let value = String(data: payload.data, encoding: .utf8),
               let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
               url.isFileURL == fileURL {
                return url
            }
        }
        return nil
    }

    private static func canonicalWebURL(_ url: URL) -> String {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.string ?? url.absoluteString
    }

    private static func preferredBinaryPayload(
        in payloads: [NormalizedPayload]
    ) -> NormalizedPayload? {
        let typePriority = [
            "public.png", "public.tiff", "public.jpeg", "public.heic",
            "com.compuserve.gif", "com.adobe.pdf"
        ]
        for type in typePriority {
            if let payload = payloads.first(where: { $0.type == type }) {
                return payload
            }
        }
        return payloads.sorted { $0.type < $1.type }.first
    }

    private static func fullPayloadIdentity(_ payloads: [NormalizedPayload]) -> Data {
        var hasher = SHA256()
        for payload in payloads.sorted(by: {
            if $0.type != $1.type { return $0.type < $1.type }
            return $0.data.lexicographicallyPrecedes($1.data)
        }) {
            update(&hasher, data: Data(payload.type.utf8))
            update(&hasher, data: payload.data)
        }
        return Data(hasher.finalize())
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
