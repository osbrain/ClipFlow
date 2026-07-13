import Foundation

public actor LocalLogger {
    private let fileURL: URL
    private let maximumBytes: Int
    private var enabled: Bool

    public init(fileURL: URL, maximumBytes: Int = 2_000_000, enabled: Bool = false) {
        self.fileURL = fileURL
        self.maximumBytes = max(64_000, maximumBytes)
        self.enabled = enabled
    }

    public func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    public func log(_ event: String, metadata: [String: String] = [:]) async {
        guard enabled else { return }

        let safeMetadata = metadata.filter { key, _ in
            !["content", "text", "payload", "clipboard"].contains(key.lowercased())
        }
        let record: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "event": event,
            "metadata": safeMetadata
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              var line = String(data: data, encoding: .utf8) else {
            return
        }
        line.append("\n")

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try rotateIfNeeded(incomingBytes: line.utf8.count)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try Data().write(to: fileURL, options: .atomic)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } catch {
            return
        }
    }

    private func rotateIfNeeded(incomingBytes: Int) throws {
        let currentSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard currentSize + incomingBytes > maximumBytes else { return }

        let backup = fileURL.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: backup)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }
}

