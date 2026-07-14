import Foundation

public enum PasteMode: String, Codable, CaseIterable, Sendable {
    case original
    case plainText
}

public final class PasteModeResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var configuredDefaultMode: PasteMode
    public let overrides: [String: PasteMode]

    public init(defaultMode: PasteMode, overrides: [String: PasteMode]) {
        self.configuredDefaultMode = defaultMode
        self.overrides = overrides
    }

    public var defaultMode: PasteMode {
        lock.withLock { configuredDefaultMode }
    }

    public func updateDefaultMode(_ mode: PasteMode) {
        lock.withLock { configuredDefaultMode = mode }
    }

    public func mode(for bundleID: String?) -> PasteMode {
        let defaultMode = lock.withLock { configuredDefaultMode }
        guard let bundleID else { return defaultMode }
        return overrides[bundleID] ?? defaultMode
    }
}
