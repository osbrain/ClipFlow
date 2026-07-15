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

    @MainActor
    @Test("brand icon is bundled at macOS app-icon resolution")
    func bundledBrandIcon() {
        let icon = ClipFlowBrandIcon.image()

        #expect(icon != nil)
        #expect(icon?.representations.map(\.pixelsWide).max() == 1_024)
        #expect(icon?.representations.map(\.pixelsHigh).max() == 1_024)
        let largestRepresentation = icon?.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide < $1.pixelsWide }
        #expect(largestRepresentation?.colorAt(x: 0, y: 0)?.alphaComponent == 0)
    }

    @Test("packaged UI resources resolve from the app Resources directory")
    func packagedResourceLocation() {
        let resourcesURL = URL(
            fileURLWithPath: "/Applications/ClipFlow.app/Contents/Resources",
            isDirectory: true
        )

        #expect(
            ClipFlowResourceBundle.packagedBundleURL(
                mainResourceURL: resourcesURL
            ) == resourcesURL.appendingPathComponent(
                "ClipFlow_ClipFlowUI.bundle",
                isDirectory: true
            )
        )
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
