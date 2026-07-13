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
}
