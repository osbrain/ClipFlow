import Foundation

public enum PasteMode: String, Codable, CaseIterable, Sendable {
    case original
    case plainText
}

public struct PasteModeResolver: Equatable, Sendable {
    public let defaultMode: PasteMode
    public let overrides: [String: PasteMode]

    public init(defaultMode: PasteMode, overrides: [String: PasteMode]) {
        self.defaultMode = defaultMode
        self.overrides = overrides
    }

    public func mode(for bundleID: String?) -> PasteMode {
        guard let bundleID else { return defaultMode }
        return overrides[bundleID] ?? defaultMode
    }
}

