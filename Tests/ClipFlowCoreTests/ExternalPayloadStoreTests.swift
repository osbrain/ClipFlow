import CryptoKit
import Foundation
import Testing
@testable import ClipFlowStorage

@Suite("Encrypted external payload storage")
struct ExternalPayloadStoreTests {
    @Test("round-trips encrypted data and detects tampering")
    func encryptedPayloadRoundTripAndTamperDetection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let key = SymmetricKey(size: .bits256)
        let store = ExternalPayloadStore(root: root, key: key)
        let plaintext = Data("secret clipboard content".utf8)
        let reference = try store.write(plaintext, id: UUID())
        let fileURL = root.appendingPathComponent(reference.fileName)
        let encryptedBytes = try Data(contentsOf: fileURL)

        #expect(encryptedBytes.range(of: plaintext) == nil)
        #expect(try store.read(reference) == plaintext)

        var tampered = encryptedBytes
        tampered[tampered.index(before: tampered.endIndex)] ^= 0xff
        try tampered.write(to: fileURL, options: .atomic)

        #expect(throws: ExternalPayloadError.authenticationFailed) {
            try store.read(reference)
        }
    }
}
