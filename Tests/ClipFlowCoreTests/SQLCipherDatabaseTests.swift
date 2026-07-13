import Foundation
import Testing
@testable import ClipFlowStorage

@Suite("SQLCipher database")
struct SQLCipherDatabaseTests {
    @Test("reports SQLCipher and rejects a wrong key")
    func reportsCipherAndRejectsWrongKey() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("ClipFlow.sqlite")
        let key = Data(repeating: 0x11, count: 32)
        do {
            let database = try SQLCipherDatabase(url: databaseURL, key: key)
            #expect(!database.cipherVersion.isEmpty)
            try database.execute("CREATE TABLE proof(value TEXT NOT NULL);")
            try database.execute("INSERT INTO proof(value) VALUES ('encrypted');")
        }

        let reopened = try SQLCipherDatabase(url: databaseURL, key: key)
        #expect(try reopened.scalarText("SELECT value FROM proof LIMIT 1;") == "encrypted")

        #expect(throws: SQLCipherDatabaseError.self) {
            _ = try SQLCipherDatabase(
                url: databaseURL,
                key: Data(repeating: 0x22, count: 32)
            )
        }
    }
}
