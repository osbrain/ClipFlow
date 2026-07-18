import Foundation
import Security

public enum KeychainKeyStoreError: Error, Equatable, Sendable {
    case unexpectedData
    case randomGenerationFailed(OSStatus)
    case keychainFailure(OSStatus)
}

public struct KeychainKeyStore: Sendable {
    private let service: String
    private let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    public func loadOrCreate() throws -> Data {
        if let existing = try load() {
            guard existing.count == 32 else {
                throw KeychainKeyStoreError.unexpectedData
            }
            return existing
        }

        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw KeychainKeyStoreError.randomGenerationFailed(randomStatus)
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: bytes
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus == errSecDuplicateItem, let existing = try load() {
            return existing
        }
        guard addStatus == errSecSuccess else {
            throw KeychainKeyStoreError.keychainFailure(addStatus)
        }
        return bytes
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainKeyStoreError.keychainFailure(status)
        }
    }

    private func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainKeyStoreError.keychainFailure(status)
        }
        guard let data = result as? Data else {
            throw KeychainKeyStoreError.unexpectedData
        }
        return data
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}

public enum DatabaseKeychainService {
    public static let legacyService = "local.clipflow.app"

    private static let markerFileName = "keychain-service"

    public static func resolvedService(
        applicationSupport: URL,
        hasExistingDatabase: Bool
    ) throws -> String {
        let markerURL = applicationSupport.appendingPathComponent(
            markerFileName,
            isDirectory: false
        )
        if let service = try? String(contentsOf: markerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !service.isEmpty {
            return service
        }

        if hasExistingDatabase {
            return legacyService
        }

        let service = "\(legacyService).\(UUID().uuidString)"
        try service.write(to: markerURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: markerURL.path
        )
        return service
    }
}
