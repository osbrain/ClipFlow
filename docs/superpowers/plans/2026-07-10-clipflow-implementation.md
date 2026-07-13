# ClipFlow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a distributable, encrypted, native macOS clipboard manager that reproduces Clipi's observable workflows under the independent ClipFlow product identity.

**Architecture:** A SwiftPM workspace separates deterministic domain logic, encrypted persistence, macOS integrations, and the SwiftUI/AppKit executable. Each capability is introduced test-first behind a protocol so storage and system permissions can fail independently without disabling clipboard history.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Combine, Carbon, ApplicationServices, CryptoKit, Security/Keychain, SQLCipher C API, XCTest, Sparkle 2, shell release scripts, Developer ID signing and Apple notarization.

---

## File Map

- `Package.swift`: products, targets, strict concurrency settings, Sparkle dependency, and macOS 14 deployment target.
- `Sources/ClipFlowCore/Models.swift`: value types shared across packages.
- `Sources/ClipFlowCore/ClipboardNormalizer.swift`: canonical previews, kinds, hashes, and size limits.
- `Sources/ClipFlowCore/SearchQuery.swift`: tokenization, filters, and deterministic ranking.
- `Sources/ClipFlowCore/RetentionPolicy.swift`: cleanup decisions that preserve favorites.
- `Sources/ClipFlowCore/PasteModeResolver.swift`: default and per-application paste behavior.
- `Sources/ClipFlowStorage/SQLCipherDatabase.swift`: connection, keying, transactions, and integrity checks.
- `Sources/ClipFlowStorage/Migrations.swift`: versioned schema creation and upgrades.
- `Sources/ClipFlowStorage/ClipboardRepository.swift`: item, payload, category, search, and cleanup persistence.
- `Sources/ClipFlowStorage/ExternalPayloadStore.swift`: AES-GCM files with atomic writes and hash verification.
- `Sources/ClipFlowSystem/PasteboardMonitor.swift`: change-count observation and self-write suppression.
- `Sources/ClipFlowSystem/SystemClipboard.swift`: capture and restoration of pasteboard representations.
- `Sources/ClipFlowSystem/GlobalHotKey.swift`: Carbon registration and event dispatch.
- `Sources/ClipFlowSystem/PasteCoordinator.swift`: target restoration and optional Command-V posting.
- `Sources/ClipFlowSystem/BrowserAutomation.swift`: Safari, Chrome, and Edge status, enumeration, and activation.
- `Sources/ClipFlowSystem/KeychainKeyStore.swift`: non-synchronizing 256-bit database key.
- `Sources/ClipFlowSystem/LoginItemService.swift`: `SMAppService` integration.
- `Sources/ClipFlowApp/ClipFlowApp.swift`: composition root and app lifecycle.
- `Sources/ClipFlowApp/AppModel.swift`: observable application state and use-case orchestration.
- `Sources/ClipFlowApp/FloatingPanelController.swift`: AppKit panel, positioning, focus, and dismissal.
- `Sources/ClipFlowApp/MainPanelView.swift`: sidebar, search, history, and details.
- `Sources/ClipFlowApp/SettingsView.swift`: storage, permissions, browser, paste, update, and diagnostics settings.
- `Sources/ClipFlowApp/OnboardingView.swift`: first-run explanations and optional permission requests.
- `Sources/ClipFlowApp/Resources/Assets.xcassets`: independent ClipFlow assets.
- `Tests/*Tests`: unit and integration tests mirroring the production target names.
- `scripts/package-app.sh`: deterministic `.app` assembly for local Command Line Tools builds.
- `scripts/release.sh`: archive, sign, notarize, DMG, appcast, and verification pipeline for full Xcode environments.

## Milestone 1: Tested Core and Runnable Native Shell

### Task 1: SwiftPM workspace and smoke test

**Files:**
- Create: `Package.swift`
- Create: `Sources/ClipFlowCore/Models.swift`
- Create: `Sources/ClipFlowApp/ClipFlowApp.swift`
- Create: `Tests/ClipFlowCoreTests/ModelsTests.swift`

- [x] **Step 1: Write a failing identity test**

```swift
import XCTest
@testable import ClipFlowCore

final class ModelsTests: XCTestCase {
    func testClipboardItemKeepsStableIdentity() {
        let id = UUID()
        let item = ClipboardItem(id: id, createdAt: .distantPast, updatedAt: .distantPast,
                                 appName: "Finder", bundleID: "com.apple.finder",
                                 kind: .text, previewText: "hello", searchText: "hello",
                                 byteSize: 5, contentHash: "abc", isFavorite: false,
                                 lastUsedAt: nil, customTitle: nil, hasExternalPayload: false)
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.displayTitle, "hello")
    }
}
```

- [x] **Step 2: Run the test and verify RED**

Run: `swift test --filter ModelsTests/testClipboardItemKeepsStableIdentity`

Expected: compilation fails because `ClipFlowCore` and `ClipboardItem` do not exist.

- [x] **Step 3: Add the package and minimal model**

```swift
// Package.swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClipFlow",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClipFlowCore", targets: ["ClipFlowCore"]),
        .executable(name: "ClipFlowApp", targets: ["ClipFlowApp"])
    ],
    targets: [
        .target(name: "ClipFlowCore"),
        .executableTarget(name: "ClipFlowApp", dependencies: ["ClipFlowCore"]),
        .testTarget(name: "ClipFlowCoreTests", dependencies: ["ClipFlowCore"])
    ]
)
```

```swift
// Sources/ClipFlowCore/Models.swift
import Foundation

public enum ClipboardKind: String, Codable, Sendable { case text, richText, image, file, link, mixed, unknown }

public struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let appName: String
    public let bundleID: String?
    public let kind: ClipboardKind
    public let previewText: String
    public let searchText: String
    public let byteSize: Int
    public let contentHash: String
    public let isFavorite: Bool
    public let lastUsedAt: Date?
    public let customTitle: String?
    public let hasExternalPayload: Bool

    public init(id: UUID, createdAt: Date, updatedAt: Date, appName: String, bundleID: String?, kind: ClipboardKind, previewText: String, searchText: String, byteSize: Int, contentHash: String, isFavorite: Bool, lastUsedAt: Date?, customTitle: String?, hasExternalPayload: Bool) {
        self.id = id; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.appName = appName; self.bundleID = bundleID; self.kind = kind
        self.previewText = previewText; self.searchText = searchText; self.byteSize = byteSize
        self.contentHash = contentHash; self.isFavorite = isFavorite; self.lastUsedAt = lastUsedAt
        self.customTitle = customTitle; self.hasExternalPayload = hasExternalPayload
    }

    public var displayTitle: String { customTitle?.isEmpty == false ? customTitle! : previewText }
}
```

```swift
// Sources/ClipFlowApp/ClipFlowApp.swift
import SwiftUI

@main struct ClipFlowApp: App {
    var body: some Scene { WindowGroup { Text("ClipFlow") } }
}
```

- [x] **Step 4: Run all tests and verify GREEN**

Run: `swift test`

Expected: `ModelsTests` passes with zero failures.

- [x] **Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: scaffold ClipFlow Swift workspace"
```

### Task 2: Clipboard normalization and deduplication identity

**Files:**
- Create: `Sources/ClipFlowCore/ClipboardNormalizer.swift`
- Create: `Tests/ClipFlowCoreTests/ClipboardNormalizerTests.swift`

- [x] **Step 1: Write failing normalization tests**

```swift
import XCTest
@testable import ClipFlowCore

final class ClipboardNormalizerTests: XCTestCase {
    func testTextCaptureNormalizesLineEndingsAndHashesRepresentations() throws {
        let capture = RawClipboardCapture(sourceAppName: "Notes", sourceBundleID: "com.apple.Notes", items: [
            RawClipboardItem(representations: [.init(type: "public.utf8-plain-text", data: Data("hello\r\nworld".utf8))])
        ])
        let result = try ClipboardNormalizer(maxRepresentationBytes: 1_000, maxCaptureBytes: 2_000).normalize(capture)
        XCTAssertEqual(result.kind, .text)
        XCTAssertEqual(result.previewText, "hello\nworld")
        XCTAssertEqual(result.payloads.count, 1)
        XCTAssertEqual(result.contentHash.count, 64)
    }

    func testOversizedRepresentationIsRejectedWithoutLosingValidSibling() throws {
        let capture = RawClipboardCapture(sourceAppName: "App", sourceBundleID: nil, items: [
            RawClipboardItem(representations: [
                .init(type: "public.data", data: Data(repeating: 1, count: 20)),
                .init(type: "public.utf8-plain-text", data: Data("ok".utf8))
            ])
        ])
        let result = try ClipboardNormalizer(maxRepresentationBytes: 10, maxCaptureBytes: 100).normalize(capture)
        XCTAssertEqual(result.payloads.map(\.type), ["public.utf8-plain-text"])
    }
}
```

- [x] **Step 2: Verify RED**

Run: `swift test --filter ClipboardNormalizerTests`

Expected: compilation fails because the raw and normalized capture APIs do not exist.

- [x] **Step 3: Implement immutable capture types and normalizer**

Implement `RawClipboardRepresentation`, `RawClipboardItem`, `RawClipboardCapture`, `NormalizedPayload`, and `NormalizedCapture`. `ClipboardNormalizer.normalize` must filter per-item limits, reject an empty result with `ClipboardNormalizationError.noUsablePayload`, normalize CRLF text to LF, classify the aggregate kind, derive preview/search text, and hash a deterministic stream of item index, type, length, and bytes using `CryptoKit.SHA256`.

- [x] **Step 4: Verify GREEN**

Run: `swift test --filter ClipboardNormalizerTests && swift test`

Expected: both normalization tests and the full suite pass.

- [x] **Step 5: Commit**

```bash
git add Sources/ClipFlowCore Tests/ClipFlowCoreTests
git commit -m "feat: normalize clipboard captures"
```

### Task 3: Search, filters, and retention decisions

**Files:**
- Create: `Sources/ClipFlowCore/SearchQuery.swift`
- Create: `Sources/ClipFlowCore/RetentionPolicy.swift`
- Create: `Tests/ClipFlowCoreTests/SearchQueryTests.swift`
- Create: `Tests/ClipFlowCoreTests/RetentionPolicyTests.swift`

- [x] **Step 1: Write failing behavior tests**

```swift
func testSearchMatchesTitleBeforeBodyAndFiltersFavorite() {
    let query = SearchQuery(text: "road map", categoryID: nil, kind: nil, favoritesOnly: true)
    let titled = ItemSearchDocument(id: UUID(), title: "Road Map", body: "x", appName: "Notes", isFavorite: true)
    let body = ItemSearchDocument(id: UUID(), title: "x", body: "road map", appName: "Notes", isFavorite: true)
    XCTAssertLessThan(query.score(titled)!, query.score(body)!)
    XCTAssertNil(query.score(.init(id: UUID(), title: "Road Map", body: "", appName: "Notes", isFavorite: false)))
}

func testRetentionPreservesFavoritesAndRemovesOldestUntilWithinBudget() {
    let decision = RetentionPolicy(maxAge: nil, maxItemCount: 2, maxBytes: 100).cleanupCandidates([
        .init(id: UUID(), timestamp: Date(timeIntervalSince1970: 1), byteSize: 70, isFavorite: false),
        .init(id: UUID(), timestamp: Date(timeIntervalSince1970: 2), byteSize: 70, isFavorite: false),
        .init(id: UUID(), timestamp: Date(timeIntervalSince1970: 3), byteSize: 70, isFavorite: true)
    ], now: Date(timeIntervalSince1970: 10))
    XCTAssertEqual(decision.count, 2)
}
```

- [x] **Step 2: Verify RED**

Run: `swift test --filter 'SearchQueryTests|RetentionPolicyTests'`

Expected: compilation fails for the missing search and retention types.

- [x] **Step 3: Implement deterministic token matching and cleanup ordering**

Use case- and diacritic-insensitive normalized tokens. Return ranking values where exact title, title prefix, title contains, body contains, and app contains are increasingly larger. Retention first removes expired non-favorites, then the oldest non-favorites until both count and byte constraints are satisfied.

- [x] **Step 4: Verify GREEN and commit**

Run: `swift test`

Expected: all core tests pass.

```bash
git add Sources/ClipFlowCore Tests/ClipFlowCoreTests
git commit -m "feat: add search and retention rules"
```

## Milestone 2: Encrypted Persistence

### Task 4: Keychain key and encrypted external payloads

**Files:**
- Create: `Sources/ClipFlowSystem/KeychainKeyStore.swift`
- Create: `Sources/ClipFlowStorage/ExternalPayloadStore.swift`
- Create: `Tests/ClipFlowStorageTests/ExternalPayloadStoreTests.swift`

- [ ] **Step 1: Write a failing round-trip and tamper test**

```swift
func testEncryptedPayloadRoundTripAndTamperDetection() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let key = SymmetricKey(size: .bits256)
    let store = ExternalPayloadStore(root: root, key: key)
    let reference = try store.write(Data("secret".utf8), id: UUID())
    XCTAssertEqual(try store.read(reference), Data("secret".utf8))
    var bytes = try Data(contentsOf: root.appendingPathComponent(reference.fileName))
    bytes[bytes.startIndex] ^= 0xff
    try bytes.write(to: root.appendingPathComponent(reference.fileName))
    XCTAssertThrowsError(try store.read(reference))
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter ExternalPayloadStoreTests`

Expected: compilation fails for `ExternalPayloadStore`.

- [ ] **Step 3: Implement versioned AES-GCM files and Keychain access**

The file format is magic `CLPF`, version byte `1`, sealed combined AES-GCM bytes, original size, and SHA-256. Writes use a sibling temporary file followed by atomic replacement. `KeychainKeyStore` stores 32 random bytes with `kSecAttrSynchronizable=false` and `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

- [ ] **Step 4: Verify GREEN and commit**

Run: `swift test --filter ExternalPayloadStoreTests && swift test`

Expected: round-trip passes and tampering throws `ExternalPayloadError.authenticationFailed`.

```bash
git add Sources/ClipFlowSystem Sources/ClipFlowStorage Tests/ClipFlowStorageTests Package.swift
git commit -m "feat: encrypt external clipboard payloads"
```

### Task 5: SQLCipher database, migrations, and repository

**Files:**
- Create: `Sources/CSQLCipher/module.modulemap`
- Create: `Sources/ClipFlowStorage/SQLCipherDatabase.swift`
- Create: `Sources/ClipFlowStorage/Migrations.swift`
- Create: `Sources/ClipFlowStorage/ClipboardRepository.swift`
- Create: `Tests/ClipFlowStorageTests/ClipboardRepositoryTests.swift`

- [ ] **Step 1: Write failing repository integration tests**

```swift
func testInsertDeduplicatesByHashAndSearchesUpdatedItem() throws {
    let harness = try RepositoryHarness()
    let first = try harness.repository.upsert(harness.capture(hash: "same", preview: "First"))
    let second = try harness.repository.upsert(harness.capture(hash: "same", preview: "Second"))
    XCTAssertEqual(first.id, second.id)
    XCTAssertEqual(try harness.repository.search(.init(text: "Second", categoryID: nil, kind: nil, favoritesOnly: false)).map(\.id), [first.id])
}

func testCategoryDeletionDoesNotDeleteClipboardItem() throws {
    let harness = try RepositoryHarness()
    let item = try harness.repository.upsert(harness.capture(hash: "a", preview: "A"))
    let category = try harness.repository.createCategory(name: "Work")
    try harness.repository.assign(itemID: item.id, categoryID: category.id)
    try harness.repository.deleteCategory(category.id)
    XCTAssertNotNil(try harness.repository.item(id: item.id))
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter ClipboardRepositoryTests`

Expected: compilation fails for the database and repository APIs.

- [ ] **Step 3: Vendor and expose SQLCipher**

Pin SQLCipher to a reviewed release in `Vendor/sqlcipher`, compile it through a C target with `SQLITE_HAS_CODEC`, `SQLITE_ENABLE_FTS5`, `SQLITE_ENABLE_JSON1`, and `SQLITE_THREADSAFE=2`, and expose only `sqlite3.h` through `CSQLCipher`. Record the upstream version and checksum in `Vendor/sqlcipher/README.md`.

- [ ] **Step 4: Implement database and schema**

Open with `sqlite3_open_v2`, call `sqlite3_key` before any query, enable foreign keys and WAL, then run `PRAGMA cipher_integrity_check`. Migrations create the tables and indexes defined in the product design plus FTS5 triggers for `custom_title`, `preview_text`, `search_text`, and `app_name`.

- [ ] **Step 5: Implement transactional repository behavior**

`upsert` must update an existing content hash, insert all payloads atomically, move large payloads through `ExternalPayloadStore`, and delete newly written files if the transaction rolls back. Category, favorite, rename, delete, search, count/bytes, cleanup, export, and backup methods use prepared statements and typed row decoding.

- [ ] **Step 6: Verify GREEN and commit**

Run: `swift test --filter ClipboardRepositoryTests && swift test`

Expected: repository tests pass and opening the database without its key fails integrity validation.

```bash
git add Vendor Sources/CSQLCipher Sources/ClipFlowStorage Tests/ClipFlowStorageTests Package.swift
git commit -m "feat: add encrypted clipboard repository"
```

## Milestone 3: macOS Clipboard, Hotkey, and Paste

### Task 6: Pasteboard capture and monitor

**Files:**
- Create: `Sources/ClipFlowSystem/SystemClipboard.swift`
- Create: `Sources/ClipFlowSystem/PasteboardMonitor.swift`
- Create: `Tests/ClipFlowSystemTests/PasteboardMonitorTests.swift`

- [ ] **Step 1: Write failing monitor tests using an injected pasteboard**

```swift
func testMonitorEmitsOncePerChangeAndIgnoresOwnWrite() async throws {
    let board = FakePasteboard(changeCount: 1)
    let monitor = PasteboardMonitor(pasteboard: board, interval: .milliseconds(10))
    let recorder = CaptureRecorder()
    await monitor.start { await recorder.append($0) }
    board.setText("first", changeCount: 2)
    try await Task.sleep(for: .milliseconds(30))
    await monitor.ignoreNextChange(expected: 3)
    board.setText("internal", changeCount: 3)
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertEqual(await recorder.values.count, 1)
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter PasteboardMonitorTests`

Expected: compilation fails for monitor and pasteboard protocols.

- [ ] **Step 3: Implement change observation and representation capture**

Define a `PasteboardAccess` protocol and an `NSPasteboard` adapter. The actor-based monitor compares change counts, supports pause/resume and one expected ignored change, snapshots all item types as `Data`, and resolves the frontmost source application through `NSWorkspace`.

- [ ] **Step 4: Verify GREEN and commit**

Run: `swift test --filter PasteboardMonitorTests && swift test`

Expected: monitor emits exactly once and the full suite passes under Thread Sanitizer when full Xcode is available.

```bash
git add Sources/ClipFlowSystem Tests/ClipFlowSystemTests Package.swift
git commit -m "feat: monitor macOS clipboard changes"
```

### Task 7: Paste restoration and per-app mode

**Files:**
- Create: `Sources/ClipFlowCore/PasteModeResolver.swift`
- Create: `Sources/ClipFlowSystem/PasteCoordinator.swift`
- Create: `Tests/ClipFlowCoreTests/PasteModeResolverTests.swift`
- Create: `Tests/ClipFlowSystemTests/PasteCoordinatorTests.swift`

- [ ] **Step 1: Write failing mode and fallback tests**

```swift
func testPerApplicationModeOverridesDefault() {
    let resolver = PasteModeResolver(defaultMode: .original, overrides: ["com.apple.Terminal": .plainText])
    XCTAssertEqual(resolver.mode(for: "com.apple.Terminal"), .plainText)
    XCTAssertEqual(resolver.mode(for: "com.apple.TextEdit"), .original)
}

func testPasteWritesClipboardEvenWhenAccessibilityIsDenied() async throws {
    let board = FakeWritablePasteboard()
    let coordinator = PasteCoordinator(board: board, accessibility: DeniedAccessibility(), activator: FakeActivator())
    let outcome = try await coordinator.paste(.fixtureText("hello"), target: .fixture)
    XCTAssertEqual(board.string, "hello")
    XCTAssertEqual(outcome, .copiedRequiresManualPaste)
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter 'PasteModeResolverTests|PasteCoordinatorTests'`

Expected: compilation fails for paste APIs.

- [ ] **Step 3: Implement original/plain writeback and Accessibility posting**

Original mode restores all item representations in stable item/type order. Plain mode chooses UTF-8 text, then extracts attributed-string text from RTF/HTML. The coordinator records the target app, writes the board, activates the target, and posts Command-V only when `AXIsProcessTrusted()` is true.

- [ ] **Step 4: Verify GREEN and commit**

Run: `swift test`

Expected: all tests pass, including denied-Accessibility fallback.

```bash
git add Sources Tests
git commit -m "feat: restore and paste clipboard items"
```

### Task 8: Global shortcut and floating panel state machine

**Files:**
- Create: `Sources/ClipFlowSystem/GlobalHotKey.swift`
- Create: `Sources/ClipFlowCore/PanelInputState.swift`
- Create: `Sources/ClipFlowApp/FloatingPanelController.swift`
- Create: `Tests/ClipFlowCoreTests/PanelInputStateTests.swift`

- [ ] **Step 1: Write failing Escape/navigation state tests**

```swift
func testEscapeClearsSearchBeforeDismissingPanel() {
    var state = PanelInputState(isVisible: true, searchText: "abc", focus: .search)
    XCTAssertEqual(state.handle(.escape), .clearSearch)
    state.searchText = ""
    XCTAssertEqual(state.handle(.escape), .dismiss)
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter PanelInputStateTests`

Expected: compilation fails for `PanelInputState`.

- [ ] **Step 3: Implement state transitions, Carbon registration, and NSPanel**

Register Command-Shift-V with `RegisterEventHotKey`, expose preset alternatives, and unregister on change. Build a non-activating-to-activating floating panel that becomes key on show, clamps its saved frame to the active screen visible frame, sends focus to search, and dismisses according to `PanelInputState`.

- [ ] **Step 4: Verify GREEN and commit**

Run: `swift test --filter PanelInputStateTests && swift test`

Expected: state tests pass and `swift run ClipFlowApp` shows the panel when invoked from the menu bar command.

```bash
git add Sources Tests
git commit -m "feat: add global shortcut and floating panel"
```

## Milestone 4: Product UI and Organization

### Task 9: App model and main panel

**Files:**
- Create: `Sources/ClipFlowApp/AppModel.swift`
- Create: `Sources/ClipFlowApp/MainPanelView.swift`
- Create: `Sources/ClipFlowApp/HistoryListView.swift`
- Create: `Sources/ClipFlowApp/DetailView.swift`
- Create: `Sources/ClipFlowApp/CategorySidebar.swift`
- Create: `Tests/ClipFlowAppTests/AppModelTests.swift`

- [ ] **Step 1: Write failing orchestration tests**

```swift
@MainActor func testSearchReloadSelectsFirstResultAndPasteMarksUsage() async throws {
    let repository = FakeRepository(items: [.fixture(preview: "Alpha"), .fixture(preview: "Beta")])
    let model = AppModel(repository: repository, pasteCoordinator: FakePasteCoordinator())
    model.searchText = "Beta"
    await model.reload()
    XCTAssertEqual(model.selectedItem?.previewText, "Beta")
    await model.pasteSelection()
    XCTAssertEqual(repository.markedUsed, [model.selectedItem!.id])
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter AppModelTests`

Expected: compilation fails for `AppModel` and repository protocol conformances.

- [ ] **Step 3: Implement observable state and Clipi-equivalent layout**

The sidebar exposes system and user categories, the center list virtualizes rows and thumbnails, and the details column is configurable. Keyboard commands cover arrows, Return, Command-Return, Space, delete, favorite, category assignment, and rename. Empty, loading, permission, unavailable-payload, and storage-error states remain navigable.

- [ ] **Step 4: Verify GREEN and commit**

Run: `swift test --filter AppModelTests && swift test`

Expected: orchestration tests pass and a manual run can search, select, copy, favorite, rename, delete, and categorize seeded records.

```bash
git add Sources/ClipFlowApp Tests/ClipFlowAppTests Package.swift
git commit -m "feat: build ClipFlow history interface"
```

### Task 10: Settings, onboarding, login item, and diagnostics

**Files:**
- Create: `Sources/ClipFlowApp/SettingsView.swift`
- Create: `Sources/ClipFlowApp/OnboardingView.swift`
- Create: `Sources/ClipFlowSystem/LoginItemService.swift`
- Create: `Sources/ClipFlowSystem/LocalLogger.swift`
- Create: `Tests/ClipFlowAppTests/SettingsModelTests.swift`

- [ ] **Step 1: Write failing settings persistence tests**

```swift
func testInvalidExternalThresholdIsClampedAndPermissionStatusRefreshes() async {
    let defaults = MemoryDefaults()
    let permissions = FakePermissions(accessibility: false)
    let model = SettingsModel(defaults: defaults, permissions: permissions)
    model.externalPayloadThresholdMB = 0
    model.save()
    XCTAssertEqual(defaults.integer(forKey: "externalPayloadThresholdMB"), 1)
    permissions.accessibility = true
    await model.refreshPermissions()
    XCTAssertTrue(model.isAccessibilityTrusted)
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter SettingsModelTests`

Expected: compilation fails for settings APIs.

- [ ] **Step 3: Implement settings and onboarding sections**

Persist shortcut, panel frame, retention, byte limits, menu bar visibility, external threshold, detail fields, per-app paste modes, browser enablement, update preference, and redacted debug logging. `SMAppService.mainApp` controls login launch. Permission buttons open exact System Settings URLs and refresh on app activation.

- [ ] **Step 4: Verify GREEN and commit**

Run: `swift test`

Expected: settings tests pass and onboarding can be completed without granting optional permissions.

```bash
git add Sources Tests
git commit -m "feat: add onboarding and settings"
```

## Milestone 5: Browser Automation and Application Actions

### Task 11: Safari, Chrome, and Edge tab adapters

**Files:**
- Create: `Sources/ClipFlowSystem/BrowserAutomation.swift`
- Create: `Tests/ClipFlowSystemTests/BrowserAutomationTests.swift`

- [ ] **Step 1: Write failing status and payload decoding tests**

```swift
func testBrowserStatusSeparatesNotInstalledNotRunningAndDenied() async {
    let workspace = FakeWorkspace(installed: [.chrome], running: [])
    let service = BrowserAutomation(workspace: workspace, runner: FakeAppleEventRunner())
    XCTAssertEqual(await service.status(for: .edge), .notInstalled)
    XCTAssertEqual(await service.status(for: .chrome), .notRunning)
    workspace.running = [.chrome]
    service.runner = FakeAppleEventRunner(error: .notAuthorized)
    XCTAssertEqual(await service.status(for: .chrome), .notAuthorized)
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter BrowserAutomationTests`

Expected: compilation fails for browser types.

- [ ] **Step 3: Implement local Apple Events adapters**

Use `NSAppleScript` for Safari and JavaScript for Automation for Chromium browsers. Enumeration returns browser, stable window/tab coordinates, title, and URL. Activation verifies the expected title and URL at the stored position before selecting; mismatch triggers refresh instead of activating the wrong tab.

- [ ] **Step 4: Verify GREEN and commit**

Run: `swift test --filter BrowserAutomationTests && swift test`

Expected: fixture decoding and status mapping pass without launching a real browser.

```bash
git add Sources/ClipFlowSystem Tests/ClipFlowSystemTests
git commit -m "feat: search and activate browser tabs"
```

### Task 12: Quick Look, drag-out, and optional app actions

**Files:**
- Create: `Sources/ClipFlowSystem/PreviewService.swift`
- Create: `Sources/ClipFlowSystem/ClipboardDragWriter.swift`
- Create: `Sources/ClipFlowSystem/ApplicationActions.swift`
- Create: `Tests/ClipFlowSystemTests/ApplicationActionsTests.swift`

- [ ] **Step 1: Write failing action availability tests**

```swift
func testActionRequiresInstalledTargetAndCompatiblePayload() {
    let actions = ApplicationActions(installedBundleIDs: ["com.larksuite.Feishu"])
    XCTAssertTrue(actions.available(for: .fixtureText("hello")).contains(.openFeishu))
    XCTAssertFalse(actions.available(for: .fixtureBinary()).contains(.openFeishu))
    XCTAssertFalse(actions.available(for: .fixtureText("hello")).contains(.askDoubao))
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter ApplicationActionsTests`

Expected: compilation fails for application actions.

- [ ] **Step 3: Implement previews, draggable representations, and guarded actions**

Quick Look uses temporary decrypted copies deleted after preview. Drag-out supplies original file URLs or promised temporary files. Feishu and Doubao actions appear only when their bundle IDs are installed, the payload is compatible, and the user enabled the action; failures restore the original pasteboard.

- [ ] **Step 4: Verify GREEN and commit**

Run: `swift test`

Expected: all action visibility and restoration tests pass.

```bash
git add Sources Tests
git commit -m "feat: add previews drag and app actions"
```

## Milestone 6: Recovery, Updates, and Release

### Task 13: Backup, import/export, migration recovery

**Files:**
- Create: `Sources/ClipFlowStorage/BackupService.swift`
- Create: `Sources/ClipFlowCore/ArchiveManifest.swift`
- Create: `Tests/ClipFlowStorageTests/BackupServiceTests.swift`

- [ ] **Step 1: Write failing restore safety tests**

```swift
func testFailedImportLeavesCurrentDatabaseUntouched() throws {
    let harness = try BackupHarness.withExistingItem("keep")
    XCTAssertThrowsError(try harness.service.importArchive(Data("broken".utf8)))
    XCTAssertEqual(try harness.repository.allItems().map(\.previewText), ["keep"])
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter BackupServiceTests`

Expected: compilation fails for backup APIs.

- [ ] **Step 3: Implement encrypted archives and staged replacement**

Export a versioned manifest, encrypted database snapshot, and encrypted external files. Import verifies manifest, hashes, database integrity, and migration compatibility in a staging directory before atomically replacing active storage. Keep the previous active storage until the next successful launch.

- [ ] **Step 4: Verify GREEN and commit**

Run: `swift test --filter BackupServiceTests && swift test`

Expected: corrupt archives fail without changing current history.

```bash
git add Sources Tests
git commit -m "feat: add encrypted backup and recovery"
```

### Task 14: Sparkle updates and release scripts

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ClipFlowApp/UpdateController.swift`
- Create: `scripts/package-app.sh`
- Create: `scripts/release.sh`
- Create: `Config/ClipFlow.entitlements`
- Create: `Config/Info.plist`
- Create: `Tests/ClipFlowAppTests/UpdateControllerTests.swift`

- [ ] **Step 1: Write failing update-state tests**

```swift
func testUpdateFailureDoesNotDisableApplication() {
    let controller = UpdateController(driver: FailingUpdateDriver())
    controller.check()
    XCTAssertEqual(controller.state, .failed("Update check failed"))
    XCTAssertTrue(controller.applicationRemainsUsable)
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter UpdateControllerTests`

Expected: compilation fails for update APIs.

- [ ] **Step 3: Integrate Sparkle behind an update driver**

Pin Sparkle 2 in `Package.swift`, expose check progress and recoverable errors, and configure an HTTPS appcast plus public EdDSA key through build settings. The updater remains disabled when feed/key configuration is absent in development builds.

- [ ] **Step 4: Implement deterministic packaging**

`package-app.sh` builds release, creates `ClipFlow.app/Contents/{MacOS,Resources,Frameworks}`, copies executable and embedded frameworks, writes the plist, and validates launch. `release.sh` requires full Xcode, builds universal slices, signs nested frameworks and app with hardened runtime, creates and signs a DMG, submits and staples notarization, verifies Gatekeeper, signs the update archive, and generates the appcast.

- [ ] **Step 5: Verify GREEN and commit**

Run: `swift test && ./scripts/package-app.sh && open artifacts/ClipFlow.app`

Expected: tests pass and the locally packaged application launches. On a release machine, `./scripts/release.sh` exits only after `spctl --assess` and `stapler validate` succeed.

```bash
git add Package.swift Sources/ClipFlowApp Config scripts Tests/ClipFlowAppTests
git commit -m "feat: package and update ClipFlow"
```

### Task 15: Performance, UI acceptance, and release gate

**Files:**
- Create: `Tests/ClipFlowPerformanceTests/SearchPerformanceTests.swift`
- Create: `Tests/ClipFlowUITests/ClipFlowUITests.swift`
- Create: `docs/acceptance/clipi-parity-checklist.md`
- Create: `scripts/verify-release.sh`

- [ ] **Step 1: Add measurable performance and workflow tests**

```swift
func testHundredThousandItemSearchLatency() throws {
    let repository = try PerformanceRepository.seeded(itemCount: 100_000)
    measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
        _ = try? repository.search(.init(text: "needle", categoryID: nil, kind: nil, favoritesOnly: false))
    }
}
```

The UI suite launches with injected temporary storage and executes onboarding, panel show, search, arrow navigation, favorite, rename, category create/assign/delete, original paste, plain paste, Settings persistence, and permission-denied banners.

- [ ] **Step 2: Verify tests expose unmet thresholds**

Run with full Xcode: `xcodebuild test -scheme ClipFlow -destination 'platform=macOS'`

Expected before final optimization: any search over 100 ms or warm panel show over 150 ms fails its assertion.

- [ ] **Step 3: Optimize only measured bottlenecks**

Use FTS query plans, prepared-statement reuse, incremental list fetches, lazy payload reads, bounded `NSCache` thumbnails, and cancellation of obsolete searches. Re-run Instruments only for tests that exceed their threshold.

- [ ] **Step 4: Record Clipi parity checks and run release verification**

The parity checklist records side-by-side results for shortcut toggle, focus, Escape behavior, every supported pasteboard type, search, categories, details, browser tabs, permission denial, login launch, update failure, multiple displays, Spaces, and restart persistence. `verify-release.sh` runs tests, package validation, entitlement inspection, signature verification, notarization validation, clean-account installation, and previous-version update installation.

- [ ] **Step 5: Commit**

```bash
git add Tests docs/acceptance scripts/verify-release.sh
git commit -m "test: add product acceptance release gate"
```

## Execution Order and Checkpoints

- Tasks 1-3 produce a tested core and runnable native shell.
- Tasks 4-5 produce encrypted durable storage.
- Tasks 6-8 produce real clipboard capture, paste, hotkey, and panel behavior.
- Tasks 9-10 produce the complete primary user experience.
- Tasks 11-12 complete browser and application integrations.
- Tasks 13-15 complete recovery, updates, distribution, performance, and parity acceptance.

After every task, run `swift test` and keep the repository clean. After Tasks 5, 8, 10, 12, and 15, package and manually launch the app. Installation of full Xcode is required before the UI-test, universal archive, signing, notarization, and release-validation commands in Tasks 14-15.
