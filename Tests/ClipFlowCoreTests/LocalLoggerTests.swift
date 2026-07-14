import Foundation
import Testing
@testable import ClipFlowSystem

@Suite("Privacy-safe local logging")
struct LocalLoggerTests {
    @Test("sensitive clipboard metadata keys never reach disk")
    func removesSensitiveMetadata() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("ClipFlow.log")
        let logger = LocalLogger(fileURL: fileURL, enabled: true)

        await logger.log(
            "capture",
            metadata: [
                "kind": "link",
                "byteCount": "128",
                "url": "https://private.example",
                "filePath": "/Users/test/Secret.txt",
                "searchText": "private query",
                "clipboardPayload": "secret"
            ]
        )

        let data = try Data(contentsOf: fileURL)
        let line = try #require(String(data: data, encoding: .utf8))
        #expect(line.contains("kind"))
        #expect(line.contains("byteCount"))
        #expect(!line.contains("private.example"))
        #expect(!line.contains("Secret.txt"))
        #expect(!line.contains("private query"))
        #expect(!line.contains("secret"))
    }
}
