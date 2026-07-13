# ClipFlow Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ClipFlow's flat sidebar-and-form interface with an adaptive, localized, content-aware macOS interface featuring rich application icons, cached local thumbnails, a two-pane history workspace, and card-based Settings.

**Architecture:** Keep encrypted storage, paste, browser, Quick Look, drag, and application-action services unchanged. Add lightweight presentation models in `ClipFlowUI`, payload-backed thumbnail generation in `ClipFlowSystem`, and a repository bridge in `ClipFlowApp`; views consume cached presentation data and never read encrypted payloads directly.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Observation, ImageIO, QuickLookThumbnailing, UniformTypeIdentifiers, Swift Package resources, Swift Testing, SQLCipher-backed existing repository.

---

## File Map

- Modify `Package.swift`: process ClipFlowUI localization resources.
- Create `Sources/ClipFlowUI/AppearancePreferences.swift`: appearance and list-density value types.
- Create `Sources/ClipFlowUI/Localization.swift`: bundle-backed localized string access.
- Create `Sources/ClipFlowUI/Resources/en.lproj/Localizable.strings`: complete English UI strings.
- Create `Sources/ClipFlowUI/Resources/zh-Hans.lproj/Localizable.strings`: complete Simplified Chinese UI strings.
- Create `Sources/ClipFlowUI/ClipFlowVisualStyle.swift`: spacing, shape, color, and material tokens.
- Create `Sources/ClipFlowUI/VisualComponents.swift`: glass cards, filter chips, badges, source labels, and metadata cards.
- Create `Sources/ClipFlowSystem/ApplicationIconProvider.swift`: cached `NSWorkspace` application icons.
- Create `Sources/ClipFlowSystem/ClipboardThumbnailService.swift`: bounded image, PDF, and file visuals.
- Create `Sources/ClipFlowUI/ClipboardVisualModel.swift`: view-safe visual descriptors and service protocol.
- Create `Sources/ClipFlowApp/AppClipboardVisualService.swift`: repository-to-thumbnail bridge.
- Modify `Sources/ClipFlowUI/AppModel.swift`: filter state, visual state, and cancellable visual loading.
- Replace `Sources/ClipFlowUI/MainPanelView.swift`: adaptive header, search, chips, and history workspace.
- Replace `Sources/ClipFlowUI/DetailView.swift`: content preview, source header, metadata cards, and actions.
- Restyle `Sources/ClipFlowUI/BrowserTabViews.swift`: match the new workspace components.
- Replace `Sources/ClipFlowUI/SettingsView.swift`: scrollable glass-section Settings.
- Modify `Sources/ClipFlowUI/SettingsModel.swift`: persist appearance and density.
- Modify `Sources/ClipFlowUI/ClipFlowRootView.swift`: apply appearance preference.
- Modify `Sources/ClipFlowApp/ClipFlowApp.swift`: compose visual services and richer isolated demo fixtures.
- Create `Sources/ClipFlowCore/DevelopmentDemoData.swift`: deterministic visual-acceptance captures.
- Create or modify tests under `Tests/ClipFlowCoreTests` for every deterministic behavior.

## Task 1: Localization, appearance, and density preferences

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ClipFlowUI/AppearancePreferences.swift`
- Create: `Sources/ClipFlowUI/Localization.swift`
- Create: `Sources/ClipFlowUI/Resources/en.lproj/Localizable.strings`
- Create: `Sources/ClipFlowUI/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/ClipFlowUI/SettingsModel.swift`
- Modify: `Sources/ClipFlowUI/ClipFlowRootView.swift`
- Test: `Tests/ClipFlowCoreTests/AppearancePreferencesTests.swift`
- Test: `Tests/ClipFlowCoreTests/SettingsModelTests.swift`

- [ ] **Step 1: Write failing appearance and localization tests**

Create `Tests/ClipFlowCoreTests/AppearancePreferencesTests.swift`:

```swift
import SwiftUI
import Testing
@testable import ClipFlowUI

@Suite("Appearance preferences")
@MainActor
struct AppearancePreferencesTests {
    @Test("maps stored appearance values to SwiftUI color schemes")
    func mapsAppearanceValues() {
        #expect(ClipFlowAppearanceMode.system.colorScheme == nil)
        #expect(ClipFlowAppearanceMode.light.colorScheme == .light)
        #expect(ClipFlowAppearanceMode.dark.colorScheme == .dark)
    }

    @Test("provides comfortable and compact row heights")
    func providesDensityMetrics() {
        #expect(ClipFlowListDensity.comfortable.rowHeight == 74)
        #expect(ClipFlowListDensity.compact.rowHeight == 62)
    }

    @Test("loads complete English and Simplified Chinese strings")
    func loadsLocalizedStrings() throws {
        #expect(L10n.string("app.name", locale: "en") == "ClipFlow")
        #expect(L10n.string("settings.title", locale: "zh-Hans") == "设置")
        #expect(L10n.string("history.search.placeholder", locale: "zh-Hans").contains("搜索"))
    }
}
```

Extend `SettingsModelTests`:

```swift
@Test("persists appearance and list density")
func persistsAppearanceAndDensity() {
    let store = MemorySettingsStore()
    let model = SettingsModel(store: store, permissions: FakePermissionStatus(accessibilityTrusted: false))
    model.appearanceMode = .dark
    model.listDensity = .compact
    model.save()

    let reloaded = SettingsModel(store: store, permissions: FakePermissionStatus(accessibilityTrusted: false))
    #expect(reloaded.appearanceMode == .dark)
    #expect(reloaded.listDensity == .compact)
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
swift run ClipFlowCoreTests
```

Expected: compilation fails because `ClipFlowAppearanceMode`, `ClipFlowListDensity`, `L10n`, and the new `SettingsModel` properties do not exist.

- [ ] **Step 3: Add package resources and preference types**

Add `defaultLocalization` to the package declaration and change the `ClipFlowUI` target:

```diff
 let package = Package(
     name: "ClipFlow",
+    defaultLocalization: "en",
     platforms: [.macOS(.v14)],
```

```swift
.target(
    name: "ClipFlowUI",
    dependencies: ["ClipFlowCore", "ClipFlowStorage", "ClipFlowSystem"],
    resources: [.process("Resources")]
)
```

Create `AppearancePreferences.swift`:

```swift
import SwiftUI

public enum ClipFlowAppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

public enum ClipFlowListDensity: String, CaseIterable, Sendable {
    case comfortable
    case compact

    public var rowHeight: CGFloat {
        switch self {
        case .comfortable: 74
        case .compact: 62
        }
    }
}
```

Create `Localization.swift`:

```swift
import Foundation

public enum L10n {
    public static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: key, table: nil)
    }

    public static func string(_ key: String, locale identifier: String) -> String {
        guard let path = Bundle.module.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
```

Add matching keys to both `.strings` files. The initial required key set is:

```text
app.name
app.privacy.subtitle
history.search.placeholder
history.empty.title
history.empty.description
filter.all
filter.favorites
filter.text
filter.richText
filter.images
filter.files
filter.links
filter.browserTabs
detail.preview
detail.paste
detail.source
detail.kind
detail.created
detail.lastUsed
detail.size
settings.title
settings.subtitle
settings.general
settings.retention
settings.permissions
settings.startup
settings.details
settings.diagnostics
settings.appearance.system
settings.appearance.light
settings.appearance.dark
settings.density.comfortable
settings.density.compact
```

The English file contains:

```text
"app.name" = "ClipFlow";
"app.privacy.subtitle" = "Encrypted clipboard history on this Mac";
"history.search.placeholder" = "Search content, apps, links, files, and browser tabs";
"history.empty.title" = "No Clipboard Items";
"history.empty.description" = "Copied content will appear here.";
"filter.all" = "All";
"filter.favorites" = "Favorites";
"filter.text" = "Text";
"filter.richText" = "Rich Text";
"filter.images" = "Images";
"filter.files" = "Files";
"filter.links" = "Links";
"filter.browserTabs" = "Browser Tabs";
"detail.preview" = "Preview";
"detail.paste" = "Paste";
"detail.source" = "Source";
"detail.kind" = "Kind";
"detail.created" = "Created";
"detail.lastUsed" = "Last Used";
"detail.size" = "Size";
"settings.title" = "Settings";
"settings.subtitle" = "Preferences, permissions, and updates";
"settings.general" = "General";
"settings.retention" = "Retention and Storage";
"settings.permissions" = "Permissions and Integrations";
"settings.startup" = "Startup and Updates";
"settings.details" = "Detail Fields";
"settings.diagnostics" = "Diagnostics";
"settings.appearance.system" = "Follow System";
"settings.appearance.light" = "Light";
"settings.appearance.dark" = "Dark";
"settings.density.comfortable" = "Comfortable";
"settings.density.compact" = "Compact";
```

The Simplified Chinese file contains the same keys with these values:

```text
"app.name" = "ClipFlow";
"app.privacy.subtitle" = "剪贴板历史已加密保存在这台 Mac 上";
"history.search.placeholder" = "搜索内容、应用、链接、文件和浏览器标签页";
"history.empty.title" = "暂无剪贴板内容";
"history.empty.description" = "复制的内容会显示在这里。";
"filter.all" = "全部";
"filter.favorites" = "收藏";
"filter.text" = "文本";
"filter.richText" = "富文本";
"filter.images" = "图片";
"filter.files" = "文件";
"filter.links" = "链接";
"filter.browserTabs" = "浏览器标签页";
"detail.preview" = "预览";
"detail.paste" = "粘贴";
"detail.source" = "来源";
"detail.kind" = "类型";
"detail.created" = "创建时间";
"detail.lastUsed" = "上次使用";
"detail.size" = "大小";
"settings.title" = "设置";
"settings.subtitle" = "偏好、授权和更新";
"settings.general" = "通用";
"settings.retention" = "保留与存储";
"settings.permissions" = "权限与集成";
"settings.startup" = "启动与更新";
"settings.details" = "详情字段";
"settings.diagnostics" = "诊断";
"settings.appearance.system" = "跟随系统";
"settings.appearance.light" = "浅色";
"settings.appearance.dark" = "深色";
"settings.density.comfortable" = "舒适";
"settings.density.compact" = "紧凑";
```

- [ ] **Step 4: Persist preferences and apply the color scheme**

Add to `SettingsModel`:

```swift
public var appearanceMode: ClipFlowAppearanceMode
public var listDensity: ClipFlowListDensity
```

Initialize and save them with stable keys:

```swift
appearanceMode = ClipFlowAppearanceMode(
    rawValue: store.string(forKey: "appearanceMode") ?? ""
) ?? .system
listDensity = ClipFlowListDensity(
    rawValue: store.string(forKey: "listDensity") ?? ""
) ?? .comfortable
```

```swift
store.set(appearanceMode.rawValue, forKey: "appearanceMode")
store.set(listDensity.rawValue, forKey: "listDensity")
```

Apply the preference in `ClipFlowRootView`:

```swift
public var body: some View {
    rootContent
        .preferredColorScheme(settings.appearanceMode.colorScheme)
}
```

Extract the existing onboarding/main conditional into the private `rootContent` view builder without changing its behavior.

- [ ] **Step 5: Verify GREEN**

Run:

```bash
swift run ClipFlowCoreTests
swift build --product ClipFlowApp
```

Expected: all existing and new tests pass; the executable builds with processed localization resources.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/ClipFlowUI Tests/ClipFlowCoreTests
git commit -m "feat: add localized appearance preferences"
```

## Task 2: Visual tokens and reusable glass components

**Files:**
- Create: `Sources/ClipFlowUI/ClipFlowVisualStyle.swift`
- Create: `Sources/ClipFlowUI/VisualComponents.swift`
- Create: `Sources/ClipFlowUI/ClipboardKindPresentation.swift`
- Test: `Tests/ClipFlowCoreTests/ClipboardKindPresentationTests.swift`

- [ ] **Step 1: Write failing kind-presentation tests**

```swift
import Testing
import ClipFlowCore
@testable import ClipFlowUI

@Suite("Clipboard kind presentation")
struct ClipboardKindPresentationTests {
    @Test("assigns distinct symbols and accents to supported kinds")
    func assignsDistinctPresentation() {
        #expect(ClipboardKind.text.presentation.symbolName == "text.alignleft")
        #expect(ClipboardKind.richText.presentation.symbolName == "doc.richtext")
        #expect(ClipboardKind.image.presentation.symbolName == "photo")
        #expect(ClipboardKind.file.presentation.symbolName == "doc")
        #expect(ClipboardKind.link.presentation.symbolName == "link")
        #expect(ClipboardKind.image.presentation.accent != ClipboardKind.text.presentation.accent)
    }
}
```

- [ ] **Step 2: Verify RED**

Run `swift run ClipFlowCoreTests`.

Expected: compilation fails because `ClipboardKind.presentation` does not exist.

- [ ] **Step 3: Implement deterministic presentation values**

Create `ClipboardKindPresentation.swift`:

```swift
import ClipFlowCore
import SwiftUI

public struct ClipboardKindPresentation: Equatable, Sendable {
    public let symbolName: String
    public let accent: ClipFlowAccent
}

public enum ClipFlowAccent: String, Equatable, Sendable {
    case blue, indigo, teal, green, orange, pink, gray

    public var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .gray: .gray
        }
    }
}

public extension ClipboardKind {
    var presentation: ClipboardKindPresentation {
        switch self {
        case .text: .init(symbolName: "text.alignleft", accent: .blue)
        case .richText: .init(symbolName: "doc.richtext", accent: .indigo)
        case .image: .init(symbolName: "photo", accent: .green)
        case .file: .init(symbolName: "doc", accent: .orange)
        case .link: .init(symbolName: "link", accent: .teal)
        case .mixed: .init(symbolName: "square.stack.3d.up", accent: .pink)
        case .unknown: .init(symbolName: "questionmark.square.dashed", accent: .gray)
        }
    }
}
```

- [ ] **Step 4: Add visual tokens and components**

Create `ClipFlowVisualStyle.swift` with only shared constants:

```swift
import SwiftUI

enum ClipFlowVisualStyle {
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 9
    static let hairlineOpacity = 0.16
    static let selectedFillOpacity = 0.18
    static let selectedBorderOpacity = 0.9
    static let panelPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 16
}
```

Create focused components in `VisualComponents.swift`:

```swift
struct GlassSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline)
            content
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(ClipFlowVisualStyle.hairlineOpacity))
        }
    }
}
```

The same file defines `GlassRow`, `FilterChip`, `ClipboardKindBadge`, `SourceApplicationLabel`, and `MetadataCard`. Each icon-only path includes `.accessibilityLabel` and `.help`.

- [ ] **Step 5: Verify GREEN and commit**

Run:

```bash
swift run ClipFlowCoreTests
swift build --product ClipFlowApp
```

Then commit:

```bash
git add Sources/ClipFlowUI Tests/ClipFlowCoreTests
git commit -m "feat: add ClipFlow visual component system"
```

## Task 3: Cached source-application icons

**Files:**
- Create: `Sources/ClipFlowSystem/ApplicationIconProvider.swift`
- Create: `Sources/ClipFlowUI/ClipboardVisualModel.swift`
- Test: `Tests/ClipFlowCoreTests/ApplicationIconProviderTests.swift`

- [ ] **Step 1: Write failing icon-resolution tests**

```swift
import Testing
@testable import ClipFlowSystem

@Suite("Application icon resolution")
struct ApplicationIconProviderTests {
    @Test("uses bundle identifier before application name fallback")
    func selectsStableLookupKey() {
        #expect(ApplicationIconLookup(bundleID: "com.apple.Notes", appName: "Notes").cacheKey == "bundle:com.apple.Notes")
        #expect(ApplicationIconLookup(bundleID: nil, appName: "Unknown").cacheKey == "name:Unknown")
    }

    @Test("uses a deterministic fallback symbol")
    func exposesFallbackSymbol() {
        #expect(ApplicationIconProvider.fallbackSymbolName == "app.dashed")
    }
}
```

- [ ] **Step 2: Verify RED**

Run `swift run ClipFlowCoreTests`.

Expected: missing `ApplicationIconLookup` and `ApplicationIconProvider` errors.

- [ ] **Step 3: Implement the cached provider**

Create `ApplicationIconProvider.swift`:

```swift
import AppKit

public struct ApplicationIconLookup: Hashable, Sendable {
    public let bundleID: String?
    public let appName: String

    public init(bundleID: String?, appName: String) {
        self.bundleID = bundleID
        self.appName = appName
    }

    public var cacheKey: String {
        if let bundleID, !bundleID.isEmpty { return "bundle:\(bundleID)" }
        return "name:\(appName)"
    }
}

@MainActor
public final class ApplicationIconProvider {
    public static let fallbackSymbolName = "app.dashed"
    private let cache = NSCache<NSString, NSImage>()

    public init() {}

    public func icon(for lookup: ApplicationIconLookup) -> NSImage? {
        if let cached = cache.object(forKey: lookup.cacheKey as NSString) { return cached }
        guard let bundleID = lookup.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: lookup.cacheKey as NSString)
        return icon
    }
}
```

Create `ClipboardVisualModel.swift`:

```swift
import AppKit
import ClipFlowCore
import Foundation

public struct ClipboardVisualDescriptor {
    public let itemID: UUID
    public let applicationIcon: NSImage?
    public let thumbnail: NSImage?
    public let kind: ClipboardKindPresentation

    public func replacingThumbnail(_ thumbnail: NSImage?) -> Self {
        Self(
            itemID: itemID,
            applicationIcon: applicationIcon,
            thumbnail: thumbnail,
            kind: kind
        )
    }
}

@MainActor
public protocol ClipboardVisualServing: AnyObject {
    func metadataVisual(for item: ClipboardItem) -> ClipboardVisualDescriptor
    func loadThumbnail(for item: ClipboardItem, maximumPixelSize: Int) async -> NSImage?
}
```

- [ ] **Step 4: Verify GREEN and commit**

Run the complete test executable and app build, then commit:

```bash
git add Sources/ClipFlowSystem Sources/ClipFlowUI Tests/ClipFlowCoreTests
git commit -m "feat: show source application icons"
```

## Task 4: Bounded local thumbnail generation

**Files:**
- Create: `Sources/ClipFlowSystem/ClipboardThumbnailService.swift`
- Create: `Sources/ClipFlowApp/AppClipboardVisualService.swift`
- Modify: `Sources/ClipFlowUI/AppModel.swift`
- Modify: `Sources/ClipFlowApp/ClipFlowApp.swift`
- Test: `Tests/ClipFlowCoreTests/ClipboardThumbnailServiceTests.swift`
- Test: `Tests/ClipFlowCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write failing thumbnail tests**

Create a test using the following known one-pixel PNG fixture:

```swift
private let onePixelPNG = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)!
```

Tests:

```swift
@Test("creates a bounded image thumbnail")
func createsBoundedThumbnail() throws {
    let service = ClipboardThumbnailService()
    let thumbnail = try #require(service.imageThumbnail(data: onePixelPNG, maximumPixelSize: 64))
    #expect(thumbnail.pixelWidth <= 64)
    #expect(thumbnail.pixelHeight <= 64)
    #expect(!thumbnail.imageData.isEmpty)
}

@Test("returns nil for corrupt image data")
func rejectsCorruptImage() {
    #expect(ClipboardThumbnailService().imageThumbnail(data: Data([0, 1, 2]), maximumPixelSize: 64) == nil)
}
```

Extend `AppModelTests` with a fake visual service and verify that metadata visuals are immediate while thumbnail results are stored only for the matching item ID.

- [ ] **Step 2: Verify RED**

Run `swift run ClipFlowCoreTests`.

Expected: missing thumbnail service and visual-loading APIs.

- [ ] **Step 3: Implement thumbnail generation**

Create `ClipboardThumbnailService.swift` using ImageIO. The worker result contains only `Data` and integer dimensions so it can cross concurrency boundaries safely:

```swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct GeneratedThumbnail: Equatable, Sendable {
    public let imageData: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
}

public struct ClipboardThumbnailService: Sendable {
    public init() {}

    public func imageThumbnail(data: Data, maximumPixelSize: Int) -> GeneratedThumbnail? {
        guard maximumPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary),
              let destinationData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                destinationData,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return GeneratedThumbnail(
            imageData: destinationData as Data,
            pixelWidth: image.width,
            pixelHeight: image.height
        )
    }
}
```

The background worker returns existing `public.file-url` values as URLs for main-actor system-icon resolution. PDF thumbnail generation uses `QLThumbnailGenerator` asynchronously, encodes the returned representation as PNG data, and returns nil on failure.

- [ ] **Step 4: Bridge encrypted repository payloads**

Create `AppClipboardVisualService` as a `@MainActor` class. It owns `ClipboardRepository`, `ApplicationIconProvider`, `ClipboardThumbnailService`, and an `NSCache<NSString, NSImage>`.

`metadataVisual(for:)` never calls `repository.payloads`. `loadThumbnail(for:maximumPixelSize:)` first checks the cache, then uses `Task.detached` to load repository payloads and generate a `GeneratedThumbnail` or resolve a file URL. After awaiting the sendable worker result, it constructs `NSImage` or asks `NSWorkspace` for a file icon on the main actor, caches it by `"\(item.id):\(item.contentHash):\(maximumPixelSize)"`, and returns nil for unsupported content.

- [ ] **Step 5: Add cancellable visual state to AppModel**

Add:

```swift
public private(set) var visuals: [UUID: ClipboardVisualDescriptor] = [:]
@ObservationIgnored private let visualService: (any ClipboardVisualServing)?
@ObservationIgnored private var thumbnailTasks: [UUID: Task<Void, Never>] = [:]
```

The initializer accepts `visualService` with a default of nil for existing tests. `reload()` fills metadata descriptors. `requestThumbnail(for:maximumPixelSize:)` cancels an older task for the item, awaits the service, verifies the item still exists, and updates only that descriptor with `descriptor.replacingThumbnail(image)`.

Compose the service in `ClipFlowApp.swift` and pass it into `AppModel`.

- [ ] **Step 6: Verify GREEN and commit**

Run:

```bash
swift run ClipFlowCoreTests
swift build --product ClipFlowApp
```

Commit:

```bash
git add Sources Tests
git commit -m "feat: generate cached clipboard thumbnails"
```

## Task 5: Adaptive header, filters, and rich history rows

**Files:**
- Create: `Sources/ClipFlowUI/HistoryFilter.swift`
- Replace: `Sources/ClipFlowUI/MainPanelView.swift`
- Modify: `Sources/ClipFlowUI/AppModel.swift`
- Modify: `Sources/ClipFlowUI/ClipFlowRootView.swift`
- Modify: `Sources/ClipFlowApp/ClipFlowApp.swift`
- Test: `Tests/ClipFlowCoreTests/HistoryFilterTests.swift`
- Test: `Tests/ClipFlowCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write failing filter-state tests**

```swift
import Testing
import ClipFlowCore
@testable import ClipFlowUI

@Suite("History filters")
struct HistoryFilterTests {
    @Test("maps chips to exactly one repository filter state")
    func mapsChipSelection() {
        #expect(HistoryFilter.kind(.image).repositoryState == HistoryRepositoryFilterState(
            kind: .image,
            categoryID: nil,
            favoritesOnly: false
        ))
        #expect(HistoryFilter.favorites.repositoryState == HistoryRepositoryFilterState(
            kind: nil,
            categoryID: nil,
            favoritesOnly: true
        ))
    }
}
```

- [ ] **Step 2: Verify RED**

Run the full test executable. Expected: missing `HistoryFilter` and `AppModel.apply`.

- [ ] **Step 3: Implement the filter model**

```swift
public enum HistoryFilter: Equatable, Sendable {
    case all
    case favorites
    case kind(ClipboardKind)
    case category(UUID)
    case browserTabs
}

public struct HistoryRepositoryFilterState: Equatable, Sendable {
    public let kind: ClipboardKind?
    public let categoryID: UUID?
    public let favoritesOnly: Bool
}

public extension HistoryFilter {
    var repositoryState: HistoryRepositoryFilterState {
        switch self {
        case .all, .browserTabs:
            .init(kind: nil, categoryID: nil, favoritesOnly: false)
        case .favorites:
            .init(kind: nil, categoryID: nil, favoritesOnly: true)
        case .kind(let kind):
            .init(kind: kind, categoryID: nil, favoritesOnly: false)
        case .category(let id):
            .init(kind: nil, categoryID: id, favoritesOnly: false)
        }
    }
}
```

`AppModel.apply(_:)` assigns `selectedKind`, `selectedCategoryID`, and `favoritesOnly` from `filter.repositoryState`. Browser-tab selection remains coordinated by `BrowserTabModel` in the view because it is not a repository filter.

- [ ] **Step 4: Replace the permanent sidebar with the approved workspace**

Add `settings: SettingsModel` and `showSettings: () -> Void` to `MainPanelView`. `ClipFlowRootView` passes the existing settings object and the AppDelegate-provided Settings closure.

Rebuild `MainPanelView` with this structure:

```swift
VStack(spacing: 0) {
    ClipFlowHeader(
        selectedItem: model.selectedItem,
        selectedVisual: model.selectedItemID.flatMap { model.visuals[$0] },
        showSettings: showSettings
    )
    HStack(spacing: 0) {
        VStack(spacing: 10) {
            HistorySearchField(
                text: $model.searchText,
                isBrowserMode: browserModel?.isShowing == true,
                resultCount: browserModel?.isShowing == true
                    ? browserModel?.filteredTabs.count ?? 0
                    : model.items.count
            )
            HistoryFilterStrip(
                model: model,
                browserModel: browserModel
            )
            if let browserModel, browserModel.isShowing {
                BrowserTabListView(model: browserModel)
            } else {
                HistoryCardList(
                    model: model,
                    density: settings.listDensity
                )
            }
        }
        .frame(minWidth: 470)

        Divider().opacity(0.35)
        if let browserModel, browserModel.isShowing {
            BrowserTabDetailView(model: browserModel)
                .frame(minWidth: 290, idealWidth: 360)
        } else {
            DetailView(
                item: model.selectedItem,
                paste: { Task { await model.pasteSelection() } },
                preview: { model.previewSelection() },
                favorite: { Task { await model.toggleFavoriteSelection() } },
                rename: beginRename,
                delete: beginDelete,
                applicationActions: model.availableApplicationActions,
                performApplicationAction: { action in
                    Task { await model.performApplicationAction(action) }
                }
            )
            .frame(minWidth: 290, idealWidth: 360)
        }
    }
}
```

Define `beginRename` and `beginDelete` as private methods that update the existing rename and delete state. Define the four private subviews with the initializer arguments shown above; they receive state and closures only and never access storage.

Use `GeometryReader` only to decide compact versus wide action labels. Do not calculate every row size manually.

`HistoryCardList` uses `ScrollView` plus `LazyVStack`, not `List`, so selected cards can use the approved material and outline. Each row:

- Reads its immediate metadata descriptor from `model.visuals`.
- Calls `model.requestThumbnail` in `.task(id: item.contentHash)` only for image, file, or mixed kinds.
- Shows a large thumbnail or kind badge.
- Shows the small source application icon beside app name.
- Uses `settings.listDensity.rowHeight`.
- Preserves context menus and `.onDrag`.

- [ ] **Step 5: Add original header and chip styling**

The header uses the ClipFlow brand icon, `L10n` strings, selected source context, and a gear button callback supplied by the composition root. Add `showSettings: () -> Void` parameters to `ClipFlowRootView` and `MainPanelView`. `AppDelegate` passes `{ [weak self] in self?.showSettings() }` while constructing the root view, reusing the existing Settings-window method without a new protocol.

- [ ] **Step 6: Verify behavior and commit**

Run tests and build. Launch with isolated demo data and verify search, chip filtering, selection, context menu, and drag provider still work.

Commit:

```bash
git add Sources Tests
git commit -m "feat: redesign ClipFlow history workspace"
```

## Task 6: Content-aware preview and icon metadata cards

**Files:**
- Create: `Sources/ClipFlowUI/DetailPresentation.swift`
- Replace: `Sources/ClipFlowUI/DetailView.swift`
- Modify: `Sources/ClipFlowUI/MainPanelView.swift`
- Modify: `Sources/ClipFlowUI/AppModel.swift`
- Modify: `Sources/ClipFlowUI/SettingsModel.swift`
- Modify: `Sources/ClipFlowApp/AppPasteService.swift`
- Test: `Tests/ClipFlowCoreTests/DetailPresentationTests.swift`
- Test: `Tests/ClipFlowCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write failing detail-presentation tests**

```swift
import Testing
import ClipFlowCore
@testable import ClipFlowUI

@Suite("Detail presentation")
struct DetailPresentationTests {
    @Test("respects enabled metadata fields")
    func respectsVisibility() {
        let visibility = DetailFieldVisibility(
            source: true,
            kind: false,
            created: true,
            lastUsed: false,
            size: true,
            formatting: true
        )
        #expect(visibility.visibleFields == [.source, .created, .size, .formatting])
    }

    @Test("selects preview modes by kind")
    func selectsPreviewMode() {
        #expect(ClipboardKind.image.detailPreviewMode == .image)
        #expect(ClipboardKind.file.detailPreviewMode == .file)
        #expect(ClipboardKind.link.detailPreviewMode == .link)
        #expect(ClipboardKind.text.detailPreviewMode == .text)
    }
}
```

Extend `AppModelTests` with a fake paste service that records an explicit mode:

```swift
@Test("pastes a compatible selection as plain text")
func pastesSelectionAsPlainText() async {
    let item = Self.item(preview: "Formatted")
    let repository = FakeHistoryRepository(items: [item])
    let pasteService = FakePasteService()
    let model = AppModel(repository: repository, pasteService: pasteService)
    await model.reload()

    await model.pasteSelectionAsPlainText()

    #expect(await pasteService.explicitModes == [.plainText])
}
```

- [ ] **Step 2: Verify RED**

Run `swift run ClipFlowCoreTests`. Expected: missing detail-presentation types.

- [ ] **Step 3: Implement detail presentation values**

Create public enums `DetailField`, `DetailPreviewMode`, and `DetailFieldVisibility`. `visibleFields` preserves the order source, kind, created, last used, size, formatting. Map clipboard kinds deterministically. Formatting displays the localized available value for `.richText` and `.mixed`, and the localized unavailable value for other kinds.

Add `showDetailSize` and `showDetailFormatting` Boolean settings. Both default to true when absent, save under keys with the same names, and participate in `SettingsSnapshot` so Settings changes persist immediately.

Extend `PasteServing` with:

```swift
func paste(item: ClipboardItem, mode: PasteMode) async throws -> PasteOutcome
```

Provide a protocol-extension fallback that calls the existing `paste(item:)` so unrelated test doubles remain source-compatible. Override it in `AppPasteService` by loading the same repository payloads and creating a `PasteRequest` with the explicit mode. Add `AppModel.pasteSelectionAsPlainText()` with the same mark-used and error handling as normal paste.

- [ ] **Step 4: Build the new detail hierarchy**

Replace the text-only detail with:

```swift
VStack(spacing: 12) {
    SelectedSourceHeader(item: item, visual: visual)
    PreviewCard(
        mode: item.kind.detailPreviewMode,
        image: visual?.thumbnail,
        text: item.previewText
    )
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
        ForEach(visibility.visibleFields, id: \.self) { field in
            MetadataCard(icon: field.symbolName, title: field.title, value: field.value(for: item))
        }
    }
    DetailActionStack(
        item: item,
        paste: paste,
        pastePlainText: pastePlainText,
        preview: preview,
        favorite: favorite,
        rename: rename,
        delete: delete,
        applicationActions: applicationActions,
        performApplicationAction: performApplicationAction
    )
}
```

Image preview uses the larger selected thumbnail. Text remains selectable. File preview shows the system icon and `item.previewText`, which already contains normalized file URL text. Link preview is local and never fetches remote metadata.

`DetailActionStack` shows the plain-text action only for text, rich-text, link, file, or mixed items. Its localized label is “Paste File Path”/“粘贴文件路径” for files and “Paste as Plain Text”/“以纯文本粘贴” for other compatible kinds.

Update the `DetailView` call in `MainPanelView` to pass the selected visual, settings, and `{ Task { await model.pasteSelectionAsPlainText() } }` closure required by the new signature.

Keep Quick Look, paste, favorite, rename, delete, and optional application actions wired to their existing closures.

- [ ] **Step 5: Verify GREEN and commit**

Run all tests and build, then commit:

```bash
git add Sources/ClipFlowUI Tests/ClipFlowCoreTests
git commit -m "feat: add content-aware clipboard details"
```

## Task 7: Card-based localized Settings

**Files:**
- Replace: `Sources/ClipFlowUI/SettingsView.swift`
- Modify: `Sources/ClipFlowUI/SettingsModel.swift`
- Modify: `Sources/ClipFlowApp/ClipFlowApp.swift`
- Modify: `Sources/ClipFlowUI/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ClipFlowUI/Resources/zh-Hans.lproj/Localizable.strings`
- Test: `Tests/ClipFlowCoreTests/SettingsModelTests.swift`

- [ ] **Step 1: Write failing segmented-retention and live-setting tests**

Extend `SettingsModelTests`:

```swift
@Test("maps retention choices to stable stored values")
func mapsRetentionChoices() {
    let store = MemorySettingsStore()
    let model = SettingsModel(store: store, permissions: FakePermissionStatus(accessibilityTrusted: false))
    model.retention = .week
    model.save()
    #expect(store.string(forKey: "retentionPolicy") == "week")
}
```

Introduce `RetentionPreference: String, CaseIterable, Sendable` with `day`, `week`, `month`, and `unlimited`; replace the untyped `retentionPolicy: String` property.

- [ ] **Step 2: Verify RED**

Run the test executable. Expected: missing `RetentionPreference` and `SettingsModel.retention`.

- [ ] **Step 3: Implement typed retention persistence**

Initialize `retention` from the existing `retentionPolicy` key so current users migrate without data loss. Save the enum raw value to the same key. Update `SettingsSnapshot` accordingly.

- [ ] **Step 4: Replace TabView and Form**

Build a single `ScrollView`:

```swift
ScrollView {
    LazyVStack(spacing: 18) {
        SettingsHeader()
        GlassSection(title: L10n.string("settings.general"), icon: "gearshape") { generalRows }
        GlassSection(title: L10n.string("settings.retention"), icon: "clock.arrow.circlepath") { retentionRows }
        GlassSection(title: L10n.string("settings.permissions"), icon: "hand.raised") { permissionRows }
        GlassSection(title: L10n.string("settings.startup"), icon: "power") { startupRows }
        GlassSection(title: L10n.string("settings.details"), icon: "list.bullet.rectangle") { detailRows }
        GlassSection(title: L10n.string("settings.diagnostics"), icon: "wrench.and.screwdriver") { diagnosticRows }
    }
    .padding(18)
}
```

Use the following retention control and equivalent compact menu pickers for shortcut, appearance, density, and paste mode:

```swift
Picker(L10n.string("settings.retention"), selection: $model.retention) {
    Text(L10n.string("retention.day")).tag(RetentionPreference.day)
    Text(L10n.string("retention.week")).tag(RetentionPreference.week)
    Text(L10n.string("retention.month")).tag(RetentionPreference.month)
    Text(L10n.string("retention.unlimited")).tag(RetentionPreference.unlimited)
}
.pickerStyle(.segmented)
```

Use icon-bearing `GlassRow` values for toggles and permission statuses.

Do not add export, import, manual update, or reset buttons until their underlying Task 13-14 services exist. Diagnostics currently exposes only the functional redacted logging toggle.

Change the Settings window content rect in `ClipFlowApp.swift` to 640 by 700 points, set a minimum size of 560 by 520 points, and keep it resizable so localized help text can expand without clipping.

- [ ] **Step 5: Localize every visible setting string**

Add these exact English/Simplified Chinese values in addition to Task 1's keys:

| Key | English | Simplified Chinese |
|---|---|---|
| `settings.shortcut` | Global Shortcut | 唤醒快捷键 |
| `settings.showMenuBar` | Show Menu Bar Item | 显示菜单栏图标 |
| `settings.launchAtLogin` | Launch at Login | 开机自启动 |
| `settings.defaultPasteMode` | Default Paste Mode | 默认粘贴方式 |
| `settings.paste.original` | Original Formatting | 保留原格式 |
| `settings.paste.plainText` | Plain Text | 纯文本 |
| `settings.appearance` | Appearance | 外观 |
| `settings.density` | List Density | 列表密度 |
| `retention.day` | One Day | 一天 |
| `retention.week` | One Week | 一周 |
| `retention.month` | One Month | 一个月 |
| `retention.unlimited` | Unlimited | 永久保留 |
| `settings.maximumItems` | Maximum Items | 最大条目数 |
| `settings.storageLimit` | Storage Limit | 存储上限 |
| `settings.externalThreshold` | Large Payload Threshold | 大内容外置阈值 |
| `settings.accessibility` | Automatic Paste | 自动粘贴 |
| `settings.permission.granted` | Granted | 已授权 |
| `settings.permission.notGranted` | Not Granted | 未授权 |
| `settings.openSystemSettings` | Open Settings | 打开系统设置 |
| `settings.browserTabs` | Browser Tab Management | 浏览器标签页管理 |
| `settings.feishuAction` | Send to Feishu Action | 发送到飞书 |
| `settings.doubaoAction` | Ask Doubao Action | 询问豆包 |
| `settings.autoUpdates` | Check for Updates Automatically | 自动检查更新 |
| `settings.showSource` | Source Application | 来源应用 |
| `settings.showKind` | Content Kind | 内容类型 |
| `settings.showCreated` | Created Time | 创建时间 |
| `settings.showLastUsed` | Last Used Time | 上次使用时间 |
| `settings.showSize` | File Size | 内容大小 |
| `settings.showFormatting` | Formatting Availability | 原格式可用性 |
| `settings.debugLogging` | Redacted Debug Logging | 脱敏调试日志 |
| `detail.formatting` | Formatting | 格式 |
| `detail.available` | Available | 可用 |
| `detail.unavailable` | Not Available | 不可用 |
| `detail.pastePlainText` | Paste as Plain Text | 以纯文本粘贴 |
| `detail.pasteFilePath` | Paste File Path | 粘贴文件路径 |

Search `SettingsView.swift` for quoted user-facing text; only localization keys, system symbols, raw setting values, and debug environment names may remain.

- [ ] **Step 6: Verify GREEN and commit**

Run tests and app build. Capture English and Simplified Chinese Settings windows using `AppleLanguages` in an isolated test launch.

Commit:

```bash
git add Sources/ClipFlowUI Tests/ClipFlowCoreTests
git commit -m "feat: redesign localized ClipFlow settings"
```

## Task 8: Browser styling, keyboard routing, and accessibility

**Files:**
- Modify: `Sources/ClipFlowUI/BrowserTabViews.swift`
- Modify: `Sources/ClipFlowUI/MainPanelView.swift`
- Modify: `Sources/ClipFlowUI/ClipFlowRootView.swift`
- Modify: `Sources/ClipFlowUI/AppModel.swift`
- Modify: `Sources/ClipFlowApp/FloatingPanelController.swift`
- Modify: `Sources/ClipFlowApp/ClipFlowApp.swift`
- Create: `Sources/ClipFlowUI/PanelCommandRouter.swift`
- Create: `Sources/ClipFlowUI/PanelInputStateStore.swift`
- Test: `Tests/ClipFlowCoreTests/PanelCommandRouterTests.swift`

- [ ] **Step 1: Write failing command-routing tests**

```swift
import Testing
@testable import ClipFlowUI

@Suite("Panel command routing")
struct PanelCommandRouterTests {
    @Test("space previews only outside active text editing")
    func routesSpace() {
        #expect(PanelCommandRouter.route(.space, state: .listFocused) == .previewSelection)
        #expect(PanelCommandRouter.route(.space, state: .searchEditing) == .insertText)
    }

    @Test("escape clears search before dismissing")
    func routesEscape() {
        #expect(PanelCommandRouter.route(.escape, state: .searchHasText) == .clearSearch)
        #expect(PanelCommandRouter.route(.escape, state: .listFocused) == .dismissPanel)
    }
}
```

- [ ] **Step 2: Verify RED**

Run the tests. Expected: missing command router types.

- [ ] **Step 3: Implement the pure command router**

Define `PanelCommand`, `PanelInputState`, and `PanelCommandAction` enums. Implement the exact mappings for Space, Return, Command-Return, Escape, Up, and Down. No AppKit types belong in the pure router.

- [ ] **Step 4: Route native key events**

Create the shared input-state object:

```swift
import Observation

@MainActor
@Observable
public final class PanelInputStateStore {
    public var state: PanelInputState = .listFocused
    public init() {}
}
```

`MainPanelView` receives this store and updates it from search focus, non-empty search text, sheets, and list interaction. `FloatingPanelController` receives the same store plus `handleCommandAction: (PanelCommandAction) -> Void`.

Add a local event monitor owned by `FloatingPanelController` only while the panel is visible. Translate key codes and modifier flags into `PanelCommand`, call `PanelCommandRouter.route(command, state: inputStateStore.state)`, and pass non-`.insertText` actions to the closure. `AppDelegate` maps actions to `AppModel.selectPrevious`, `selectNext`, `previewSelection`, `pasteSelection`, search clearing, or panel dismissal. Remove the monitor when hidden or deinitialized.

Do not intercept ordinary text input. Search editing receives Space and printable keys normally.

- [ ] **Step 5: Restyle browser tabs and audit accessibility**

Use the same card list, source icon, selected outline, empty-state card, and detail action styling for browser tabs. Add accessibility labels for thumbnails, source icons, filter chips, Quick Look, favorite, rename, delete, refresh, paste, and Settings.

Decorative thumbnail images use `.accessibilityHidden(true)` when adjacent text already describes the item.

- [ ] **Step 6: Verify GREEN and commit**

Run tests and build. Manually verify search typing still accepts spaces and that Space previews only with list focus.

Commit:

```bash
git add Sources/ClipFlowUI Sources/ClipFlowApp Tests/ClipFlowCoreTests
git commit -m "feat: polish browser and keyboard experience"
```

## Task 9: Rich demo fixtures and native visual acceptance

**Files:**
- Create: `Sources/ClipFlowCore/DevelopmentDemoData.swift`
- Modify: `Sources/ClipFlowApp/ClipFlowApp.swift`
- Create: `docs/acceptance/clipflow-visual-redesign-checklist.md`
- Create: `scripts/capture-visual-acceptance.sh`
- Test: `Tests/ClipFlowCoreTests/DevelopmentDemoDataTests.swift`

- [ ] **Step 1: Write failing fixture tests**

```swift
import Testing
import ClipFlowCore

@Suite("Development demo data")
struct DevelopmentDemoDataTests {
    @Test("covers every primary visual kind")
    func coversVisualKinds() throws {
        let captures = DevelopmentDemoData.captures(now: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(Set(captures.map(\.kind)).isSuperset(of: [.text, .richText, .image, .file, .link]))
    }
}
```

`DevelopmentDemoData` is a public pure-data factory in `ClipFlowCore`, so the executable target imports it without making the executable itself testable.

- [ ] **Step 2: Verify RED**

Run the test executable. Expected: missing demo-data factory.

- [ ] **Step 3: Implement deterministic visual fixtures**

Create captures for:

- Multi-line plain text from Notes.
- RTF from TextEdit.
- One-pixel PNG from Preview.
- Existing temporary file URL from Finder.
- HTTPS link from Safari.

Use deterministic timestamps, source names, bundle IDs, hashes, and payloads. `CLIPFLOW_SEED_DEMO=1` inserts these fixtures only into `CLIPFLOW_DEVELOPMENT_DATA_DIR` and never into release storage.

- [ ] **Step 4: Add deterministic capture script**

`scripts/capture-visual-acceptance.sh` must:

1. Require a Debug `ClipFlowApp` executable.
2. Create a fresh temporary data directory.
3. Launch dark Chinese wide main-panel fixture.
4. Capture the main window by window ID.
5. Repeat for light English, compact window, Settings, browser empty state, and Quick Look.
6. Save PNG files under `artifacts/visual-acceptance/`.
7. Terminate only the process it launched.

Use `swift` with CoreGraphics for window enumeration and `screencapture -l` for capture. The script must not read or overwrite the user's general clipboard.

- [ ] **Step 5: Record the acceptance checklist**

The checklist contains explicit pass/fail rows for:

- Wide and compact clipping.
- Dark and light contrast.
- Chinese and English localization.
- App icons and kind badges.
- Image and file thumbnails.
- Selection outline and hover state.
- Search and filter chips.
- Detail cards and primary paste action.
- Settings section spacing and control alignment.
- Browser states.
- Quick Look.
- Keyboard focus and accessibility labels.

- [ ] **Step 6: Run final verification**

Run:

```bash
git diff --check
swift build --product ClipFlowApp
swift run ClipFlowCoreTests
./scripts/capture-visual-acceptance.sh
```

Expected:

- `git diff --check` prints no errors.
- The app build exits 0.
- Every test passes with zero issues.
- All required PNGs exist and show no clipping, overlap, missing localization, or unintended fallback icons.
- Known SQLCipher/OpenSSL minimum-version linker warnings remain documented and do not count as visual-redesign acceptance.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests scripts docs/acceptance
git commit -m "test: verify ClipFlow visual redesign"
```

The PNG outputs remain under the ignored `artifacts/visual-acceptance/` directory for local review and are not committed.

## Execution Notes

- Work on `feature/clipflow-product`; do not implement directly on `main` or `master`.
- Use the development executable test runner because Command Line Tools XCTest support is broken in this environment.
- Run `./scripts/bootstrap-dev-deps.sh` if SQLCipher/OpenSSL development bottles are missing.
- Preserve all existing encrypted storage and clipboard functionality while replacing views.
- After every task, run `swift run ClipFlowCoreTests` and keep the worktree clean with a focused commit.
- Full Xcode remains required for UI tests, universal archive, Developer ID signing, notarization, and final distributable validation.
