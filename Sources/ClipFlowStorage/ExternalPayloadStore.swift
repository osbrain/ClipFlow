import CryptoKit
import Foundation

public struct ExternalPayloadReference: Codable, Equatable, Sendable {
    public let fileName: String
    public let byteSize: Int
    public let sha256: String

    public init(fileName: String, byteSize: Int, sha256: String) {
        self.fileName = fileName
        self.byteSize = byteSize
        self.sha256 = sha256
    }
}

public enum ExternalPayloadError: Error, Equatable, Sendable {
    case invalidFormat
    case authenticationFailed
    case integrityMismatch
}

public struct ExternalPayloadStore: Sendable {
    private static let magic = Data([0x43, 0x4c, 0x50, 0x46])
    private static let version: UInt8 = 1
    private static let headerSize = 4 + 1 + 8 + 32

    private let root: URL
    private let key: SymmetricKey

    public init(root: URL, key: SymmetricKey) {
        self.root = root
        self.key = key
    }

    public func write(_ plaintext: Data, id: UUID) throws -> ExternalPayloadReference {
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        let digest = Data(SHA256.hash(data: plaintext))
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw ExternalPayloadError.invalidFormat
        }

        var file = Self.magic
        file.append(Self.version)
        file.append(Self.bigEndianBytes(UInt64(plaintext.count)))
        file.append(digest)
        file.append(combined)

        let fileName = "\(id.uuidString.lowercased()).clipflowpayload"
        let destination = root.appendingPathComponent(fileName, isDirectory: false)
        try file.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])

        return ExternalPayloadReference(
            fileName: fileName,
            byteSize: plaintext.count,
            sha256: Self.hex(digest)
        )
    }

    public func read(_ reference: ExternalPayloadReference) throws -> Data {
        let fileURL = root.appendingPathComponent(reference.fileName, isDirectory: false)
        let file = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard file.count > Self.headerSize else {
            throw ExternalPayloadError.invalidFormat
        }

        var cursor = file.startIndex
        let magicEnd = cursor + Self.magic.count
        guard file[cursor..<magicEnd] == Self.magic else {
            throw ExternalPayloadError.invalidFormat
        }
        cursor = magicEnd

        guard file[cursor] == Self.version else {
            throw ExternalPayloadError.invalidFormat
        }
        cursor += 1

        let sizeEnd = cursor + 8
        let storedSize = Self.decodeBigEndianUInt64(file[cursor..<sizeEnd])
        cursor = sizeEnd

        let digestEnd = cursor + 32
        let storedDigest = Data(file[cursor..<digestEnd])
        cursor = digestEnd

        let sealedData = Data(file[cursor...])
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: sealedData)
            plaintext = try AES.GCM.open(box, using: key)
        } catch {
            throw ExternalPayloadError.authenticationFailed
        }

        let digest = Data(SHA256.hash(data: plaintext))
        guard storedSize == UInt64(plaintext.count),
              reference.byteSize == plaintext.count,
              storedDigest == digest,
              reference.sha256 == Self.hex(digest) else {
            throw ExternalPayloadError.integrityMismatch
        }

        return plaintext
    }

    public func delete(_ reference: ExternalPayloadReference) throws {
        let fileURL = root.appendingPathComponent(reference.fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private static func bigEndianBytes(_ value: UInt64) -> Data {
        var bigEndian = value.bigEndian
        return withUnsafeBytes(of: &bigEndian) { Data($0) }
    }

    private static func decodeBigEndianUInt64(_ bytes: Data.SubSequence) -> UInt64 {
        bytes.reduce(UInt64(0)) { result, byte in
            (result << 8) | UInt64(byte)
        }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

