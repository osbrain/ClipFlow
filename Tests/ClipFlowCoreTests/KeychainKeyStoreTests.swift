import Foundation
import Testing
@testable import ClipFlowSystem

@Suite("Keychain database key")
struct KeychainKeyStoreTests {
    @Test("creates a 256-bit key once and reuses it")
    func createsAndReusesDatabaseKey() throws {
        let service = "local.clipflow.tests.\(UUID().uuidString)"
        let store = KeychainKeyStore(service: service, account: "database-key")
        defer { try? store.delete() }

        let first = try store.loadOrCreate()
        let second = try store.loadOrCreate()

        #expect(first.count == 32)
        #expect(second == first)
    }

    @Test("fresh installs use a persisted install-scoped keychain service")
    func freshInstallUsesPersistedInstallScopedService() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let first = try DatabaseKeychainService.resolvedService(
            applicationSupport: root,
            hasExistingDatabase: false
        )
        let second = try DatabaseKeychainService.resolvedService(
            applicationSupport: root,
            hasExistingDatabase: false
        )

        #expect(first != DatabaseKeychainService.legacyService)
        #expect(first.hasPrefix("\(DatabaseKeychainService.legacyService)."))
        #expect(second == first)
    }

    @Test("legacy databases keep using the original keychain service")
    func legacyDatabaseKeepsOriginalService() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let service = try DatabaseKeychainService.resolvedService(
            applicationSupport: root,
            hasExistingDatabase: true
        )

        #expect(service == DatabaseKeychainService.legacyService)
    }
}
