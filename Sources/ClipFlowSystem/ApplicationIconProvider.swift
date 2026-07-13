import AppKit
import Foundation

public struct ApplicationIconLookup: Hashable, Sendable {
    public let bundleID: String?
    public let appName: String

    public init(bundleID: String?, appName: String) {
        self.bundleID = bundleID
        self.appName = appName
    }

    public var cacheKey: String {
        if let bundleID, !bundleID.isEmpty {
            return "bundle:\(bundleID)"
        }
        return "name:\(appName)"
    }
}

@MainActor
public final class ApplicationIconProvider {
    public static let fallbackSymbolName = "app.dashed"

    private let cache = NSCache<NSString, NSImage>()

    public init() {}

    public func icon(for lookup: ApplicationIconLookup) -> NSImage? {
        let cacheKey = lookup.cacheKey as NSString
        if let cachedIcon = cache.object(forKey: cacheKey) {
            return cachedIcon
        }

        guard let bundleID = lookup.bundleID,
              !bundleID.isEmpty,
              let applicationURL = NSWorkspace.shared.urlForApplication(
                  withBundleIdentifier: bundleID
              ) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        cache.setObject(icon, forKey: cacheKey)
        return icon
    }
}
