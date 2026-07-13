import AppKit
import ClipFlowCore
import Testing
@testable import ClipFlowSystem
@testable import ClipFlowUI

@Suite("Application icon provider")
struct ApplicationIconProviderTests {
    @Test("bundle identifier is preferred for the cache key")
    func bundleIdentifierCacheKey() {
        let lookup = ApplicationIconLookup(
            bundleID: "com.apple.Notes",
            appName: "Notes"
        )

        #expect(lookup.cacheKey == "bundle:com.apple.Notes")
    }

    @Test("missing bundle identifier falls back to the application name")
    func missingBundleIdentifierCacheKey() {
        let lookup = ApplicationIconLookup(bundleID: nil, appName: "Unknown")

        #expect(lookup.cacheKey == "name:Unknown")
    }

    @Test("empty bundle identifier falls back to the application name")
    func emptyBundleIdentifierCacheKey() {
        let lookup = ApplicationIconLookup(bundleID: "", appName: "Unknown")

        #expect(lookup.cacheKey == "name:Unknown")
    }

    @MainActor
    @Test("provider exposes a stable fallback symbol")
    func fallbackSymbolName() {
        #expect(ApplicationIconProvider.fallbackSymbolName == "app.dashed")
    }

    @Test("replacing a thumbnail preserves descriptor metadata")
    func replacingThumbnail() {
        let itemID = UUID()
        let applicationIcon = NSImage(size: NSSize(width: 16, height: 16))
        let replacement = NSImage(size: NSSize(width: 32, height: 32))
        let kind = ClipboardKind.image.presentation
        let descriptor = ClipboardVisualDescriptor(
            itemID: itemID,
            applicationIcon: applicationIcon,
            thumbnail: nil,
            kind: kind
        )

        let replaced = descriptor.replacingThumbnail(replacement)

        #expect(replaced.itemID == itemID)
        #expect(replaced.applicationIcon === applicationIcon)
        #expect(replaced.thumbnail === replacement)
        #expect(replaced.kind == kind)
    }
}
