import ClipFlowCore
import CryptoKit
import Foundation
import Security

public enum ClipboardBackupError: Error, Equatable, LocalizedError {
    case emptyPassword
    case invalidArchive
    case unsupportedVersion(Int)
    case decryptionFailed
    case resourceLimitExceeded

    public var errorDescription: String? {
        switch self {
        case .emptyPassword:
            "Backup password cannot be empty."
        case .invalidArchive:
            "The selected file is not a valid ClipFlow backup."
        case .unsupportedVersion(let version):
            "This ClipFlow backup version is not supported: \(version)."
        case .decryptionFailed:
            "The backup could not be decrypted. Check the password and try again."
        case .resourceLimitExceeded:
            "The backup exceeds ClipFlow's import safety limit."
        }
    }
}

public enum ClipboardBackupImportLimits {
    public static let maximumArchiveBytes = 250 * 1_024 * 1_024
}

public struct ClipboardBackupImportResult: Equatable, Sendable {
    public let insertedItemCount: Int
    public let mergedItemCount: Int
    public let createdCategoryCount: Int
    public let restoredQuickPasteSlotCount: Int

    public init(
        insertedItemCount: Int,
        mergedItemCount: Int,
        createdCategoryCount: Int,
        restoredQuickPasteSlotCount: Int
    ) {
        self.insertedItemCount = insertedItemCount
        self.mergedItemCount = mergedItemCount
        self.createdCategoryCount = createdCategoryCount
        self.restoredQuickPasteSlotCount = restoredQuickPasteSlotCount
    }
}

struct ClipboardBackupDocument: Codable, Equatable {
    let version: Int
    let exportedAt: Date
    let items: [ClipboardBackupItem]
    let categories: [ClipboardBackupCategory]
    let itemCategories: [ClipboardBackupItemCategory]
    let quickPasteSlots: [ClipboardBackupQuickPasteSlot]
}

struct ClipboardBackupItem: Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let appName: String
    let bundleID: String?
    let kind: ClipboardKind
    let previewText: String
    let searchText: String
    let byteSize: Int
    let contentHash: String
    let isFavorite: Bool
    let lastUsedAt: Date?
    let customTitle: String?
    let recognizedText: String?
    let payloads: [ClipboardBackupPayload]
}

struct ClipboardBackupPayload: Codable, Equatable {
    let itemIndex: Int
    let type: String
    let data: Data
}

struct ClipboardBackupCategory: Codable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date
    let sortOrder: Int
}

struct ClipboardBackupItemCategory: Codable, Equatable {
    let itemID: UUID
    let categoryID: UUID
}

struct ClipboardBackupQuickPasteSlot: Codable, Equatable {
    let index: Int
    let itemID: UUID
}

enum EncryptedBackupCodec {
    static let currentVersion = 1
    private static let magic = "ClipFlowBackup"
    private static let kdfName = "PBKDF2-HMAC-SHA256"
    private static let cipherName = "AES-256-GCM"
    private static let iterations = 120_000
    private static let maximumItemCount = 20_000
    private static let maximumPayloadBytes = 25 * 1_024 * 1_024
    private static let maximumTotalPayloadBytes = 250 * 1_024 * 1_024

    static func seal(_ document: ClipboardBackupDocument, password: String) throws -> Data {
        let passwordData = try validatedPasswordData(password)
        let plaintext = try JSONEncoder.clipFlowBackup.encode(document)
        let salt = try randomData(byteCount: 16)
        let key = try deriveKey(passwordData: passwordData, salt: salt, iterations: iterations)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        guard let combined = sealed.combined else {
            throw ClipboardBackupError.invalidArchive
        }
        let envelope = ClipboardBackupEnvelope(
            magic: magic,
            version: currentVersion,
            kdf: kdfName,
            cipher: cipherName,
            iterations: iterations,
            salt: salt,
            ciphertext: combined
        )
        return try JSONEncoder.clipFlowBackup.encode(envelope)
    }

    static func open(_ data: Data, password: String) throws -> ClipboardBackupDocument {
        let passwordData = try validatedPasswordData(password)
        let envelope: ClipboardBackupEnvelope
        do {
            envelope = try JSONDecoder.clipFlowBackup.decode(
                ClipboardBackupEnvelope.self,
                from: data
            )
        } catch {
            throw ClipboardBackupError.invalidArchive
        }
        guard envelope.magic == magic,
              envelope.kdf == kdfName,
              envelope.cipher == cipherName else {
            throw ClipboardBackupError.invalidArchive
        }
        guard envelope.version == currentVersion else {
            throw ClipboardBackupError.unsupportedVersion(envelope.version)
        }
        guard envelope.iterations == iterations,
              envelope.salt.count == 16,
              envelope.ciphertext.count >= 28 else {
            throw ClipboardBackupError.invalidArchive
        }

        do {
            let key = try deriveKey(
                passwordData: passwordData,
                salt: envelope.salt,
                iterations: envelope.iterations
            )
            let sealed = try AES.GCM.SealedBox(combined: envelope.ciphertext)
            let plaintext = try AES.GCM.open(sealed, using: key)
            let document = try JSONDecoder.clipFlowBackup.decode(
                ClipboardBackupDocument.self,
                from: plaintext
            )
            guard document.version == currentVersion else {
                throw ClipboardBackupError.unsupportedVersion(document.version)
            }
            try validateResourceLimits(document)
            return document
        } catch let error as ClipboardBackupError {
            throw error
        } catch {
            throw ClipboardBackupError.decryptionFailed
        }
    }

    private static func validateResourceLimits(_ document: ClipboardBackupDocument) throws {
        guard document.items.count <= maximumItemCount else {
            throw ClipboardBackupError.resourceLimitExceeded
        }
        var totalBytes = 0
        for payload in document.items.flatMap(\.payloads) {
            guard payload.data.count <= maximumPayloadBytes,
                  totalBytes <= maximumTotalPayloadBytes - payload.data.count else {
                throw ClipboardBackupError.resourceLimitExceeded
            }
            totalBytes += payload.data.count
        }
    }

    private static func validatedPasswordData(_ password: String) throws -> Data {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = password.data(using: .utf8) else {
            throw ClipboardBackupError.emptyPassword
        }
        return data
    }

    private static func deriveKey(
        passwordData: Data,
        salt: Data,
        iterations: Int
    ) throws -> SymmetricKey {
        guard iterations > 0 else { throw ClipboardBackupError.invalidArchive }
        var block = salt
        block.append(contentsOf: [0, 0, 0, 1] as [UInt8])

        let passwordKey = SymmetricKey(data: passwordData)
        var u = Data(HMAC<SHA256>.authenticationCode(for: block, using: passwordKey))
        var output = u
        for _ in 1..<iterations {
            u = Data(HMAC<SHA256>.authenticationCode(for: u, using: passwordKey))
            for index in output.indices {
                output[index] ^= u[index]
            }
        }
        return SymmetricKey(data: output.prefix(32))
    }

    typealias RandomDataGenerator = (
        _ count: Int,
        _ bytes: UnsafeMutableRawPointer
    ) -> OSStatus

    static func randomData(
        byteCount: Int,
        generator: RandomDataGenerator = { count, bytes in
            SecRandomCopyBytes(kSecRandomDefault, count, bytes)
        }
    ) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = bytes.withUnsafeMutableBytes { buffer in
            generator(byteCount, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw ClipboardBackupError.invalidArchive
        }
        return Data(bytes)
    }
}

private struct ClipboardBackupEnvelope: Codable, Equatable {
    let magic: String
    let version: Int
    let kdf: String
    let cipher: String
    let iterations: Int
    let salt: Data
    let ciphertext: Data
}

private extension JSONEncoder {
    static var clipFlowBackup: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var clipFlowBackup: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
