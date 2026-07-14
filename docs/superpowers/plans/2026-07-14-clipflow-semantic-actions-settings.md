# ClipFlow Semantic Actions and Complete Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct real macOS clipboard classification, provide content-specific actions, make every visible setting honest and live, and add an in-app live language switch.

**Architecture:** Classification becomes a pure per-pasteboard-item semantic resolver using UTType conformance and payload-content fallbacks. A typed context-action layer separates action availability from SwiftUI rendering, while an application settings coordinator applies persisted changes to live services and repository cleanup. Localization uses a thread-safe explicit language override configured by the shared observable settings model.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, UniformTypeIdentifiers, Observation, SQLCipher, Swift Testing, macOS 14+.

---

### Task 1: Semantic clipboard classification and existing-item repair

**Files:**
- Modify: `Sources/ClipFlowCore/ClipboardNormalizer.swift`
- Modify: `Sources/ClipFlowStorage/ClipboardRepository.swift`
- Modify: `Sources/ClipFlowApp/ClipFlowApp.swift`
- Modify: `Tests/ClipFlowCoreTests/ClipboardNormalizerTests.swift`
- Modify: `Tests/ClipFlowCoreTests/ClipboardRepositoryTests.swift`

- [ ] **Step 1: Write failing semantic-classification tests**

Add real multi-representation cases to `ClipboardNormalizerTests`:

```swift
@Test("Finder companion formats remain a file")
func finderRepresentationsClassifyAsFile() throws {
    let fileURL = URL(fileURLWithPath: "/tmp/report.pdf")
    let result = try normalizer.normalize(capture(representations: [
        .init(type: "public.file-url", data: fileURL.dataRepresentation),
        .init(type: "public.utf8-plain-text", data: Data(fileURL.path.utf8)),
        .init(type: "com.apple.finder.node", data: Data([1, 2, 3]))
    ]))
    #expect(result.kind == .file)
}

@Test("Browser URL and title formats remain a link")
func browserRepresentationsClassifyAsLink() throws {
    let result = try normalizer.normalize(capture(representations: [
        .init(type: "public.url", data: Data("https://example.com".utf8)),
        .init(type: "public.utf8-plain-text", data: Data("Example".utf8)),
        .init(type: "org.chromium.source-url", data: Data("https://example.com".utf8))
    ]))
    #expect(result.kind == .link)
}

@Test("Plain web URL text becomes a link but prose remains text")
func infersLinksFromPlainText() throws {
    #expect(try normalizeText("https://example.com/path").kind == .link)
    #expect(try normalizeText("Read https://example.com later").kind == .text)
}

@Test("Multiple files are files while heterogeneous items are mixed")
func aggregatesSemanticItemKinds() throws {
    #expect(try normalizer.normalize(multiFileCapture()).kind == .file)
    #expect(try normalizer.normalize(fileAndTextCapture()).kind == .mixed)
}
```

Use these private test helpers in the same suite:

```swift
private let normalizer = ClipboardNormalizer(
    maxRepresentationBytes: 1_000_000,
    maxCaptureBytes: 5_000_000
)

private func capture(
    representations: [RawClipboardRepresentation]
) -> RawClipboardCapture {
    RawClipboardCapture(
        sourceAppName: "Test",
        sourceBundleID: "local.clipflow.tests",
        items: [RawClipboardItem(representations: representations)]
    )
}

private func normalizeText(_ value: String) throws -> NormalizedCapture {
    try normalizer.normalize(capture(representations: [
        .init(type: "public.utf8-plain-text", data: Data(value.utf8))
    ]))
}

private func multiFileCapture() -> RawClipboardCapture {
    RawClipboardCapture(
        sourceAppName: "Finder",
        sourceBundleID: "com.apple.finder",
        items: ["a.txt", "b.txt"].map { name in
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            return RawClipboardItem(representations: [
                .init(type: "public.file-url", data: url.dataRepresentation),
                .init(type: "public.utf8-plain-text", data: Data(url.path.utf8))
            ])
        }
    )
}

private func fileAndTextCapture() -> RawClipboardCapture {
    RawClipboardCapture(
        sourceAppName: "Test",
        sourceBundleID: nil,
        items: [
            RawClipboardItem(representations: [
                .init(
                    type: "public.file-url",
                    data: URL(fileURLWithPath: "/tmp/a.txt").dataRepresentation
                )
            ]),
            RawClipboardItem(representations: [
                .init(type: "public.utf8-plain-text", data: Data("note".utf8))
            ])
        ]
    )
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift run ClipFlowCoreTests
```

Expected: the Finder/browser/plain-URL tests fail because the current aggregate classifier returns `.mixed` or `.text`.

- [ ] **Step 3: Implement per-item semantic resolution**

In `ClipboardNormalizer.swift`, import `UniformTypeIdentifiers`, group accepted payloads by `itemIndex`, and resolve one semantic kind per item:

```swift
private static func aggregateKind(for payloads: [NormalizedPayload]) -> ClipboardKind {
    let itemKinds = Dictionary(grouping: payloads, by: \.itemIndex)
        .sorted { $0.key < $1.key }
        .map { semanticKind(for: $0.value) }
    let recognized = Set(itemKinds)
    return recognized.count == 1 ? recognized.first ?? .unknown : .mixed
}

private static func semanticKind(for payloads: [NormalizedPayload]) -> ClipboardKind {
    if payloads.contains(where: isFileRepresentation) { return .file }
    if payloads.contains(where: isURLRepresentation) { return .link }
    if payloads.contains(where: isImageRepresentation) { return .image }
    if payloads.contains(where: isRichTextRepresentation) { return .richText }
    if let text = decodedPlainText(in: payloads) {
        if inferredFileURL(from: text) != nil { return .file }
        if inferredWebURL(from: text) != nil { return .link }
        return .text
    }
    return .unknown
}
```

Use `UTType(payload.type)?.conforms(to:)` first, then exact legacy identifiers for Finder file lists and common image/text types. A text URL must occupy the complete trimmed string and use `http`, `https`, or `mailto`; `file://` is the only text form inferred as a file.

- [ ] **Step 4: Add repository reclassification and tests**

Add a repository method that reconstructs a `RawClipboardCapture` from each stored item's payloads, normalizes it, and updates only `kind`, `preview_text`, and `search_text` when they changed:

```swift
public func reclassifyStoredItems(using normalizer: ClipboardNormalizer) throws -> Int
```

Test that an existing `.mixed` Finder record becomes `.file` while ID, favorite, custom title, categories, timestamps, and content hash remain unchanged. Invoke the repair once at startup before the first model reload.

- [ ] **Step 5: Verify GREEN and commit**

Run `swift run ClipFlowCoreTests`; expect all classification and repository tests to pass. Commit:

```bash
git add Sources/ClipFlowCore/ClipboardNormalizer.swift Sources/ClipFlowStorage/ClipboardRepository.swift Sources/ClipFlowApp/ClipFlowApp.swift Tests/ClipFlowCoreTests/ClipboardNormalizerTests.swift Tests/ClipFlowCoreTests/ClipboardRepositoryTests.swift
git commit -m "fix: classify clipboard objects semantically"
```

### Task 2: Typed content-specific detail actions

**Files:**
- Create: `Sources/ClipFlowUI/ItemContextAction.swift`
- Modify: `Sources/ClipFlowUI/AppModel.swift`
- Modify: `Sources/ClipFlowUI/DetailView.swift`
- Modify: `Sources/ClipFlowUI/MainPanelView.swift`
- Modify: `Sources/ClipFlowApp/AppItemIntegrationService.swift`
- Modify: `Sources/ClipFlowUI/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ClipFlowUI/Resources/zh-Hans.lproj/Localizable.strings`
- Create: `Tests/ClipFlowCoreTests/ItemContextActionTests.swift`
- Modify: `Tests/ClipFlowCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write failing action-matrix tests**

Define expected action sets before production code exists:

```swift
#expect(ItemContextAction.available(for: .file) == [
    .pasteOriginal, .pasteFilePath, .openFile, .revealInFinder, .quickLook
])
#expect(ItemContextAction.available(for: .link) == [
    .pasteOriginal, .openLink, .pastePlainText
])
#expect(ItemContextAction.available(for: .image) == [
    .pasteOriginal, .quickLook
])
```

Add AppModel tests proving integration actions report localized errors without changing the selected item.

- [ ] **Step 2: Run tests and verify RED**

Run `swift run ClipFlowCoreTests`; expect compile failure because `ItemContextAction` and the new integration methods do not exist.

- [ ] **Step 3: Implement the pure action model**

Create:

```swift
public enum ItemContextAction: String, CaseIterable, Equatable, Sendable {
    case pasteOriginal, pastePlainText, pasteFilePath
    case openLink, openFile, revealInFinder, quickLook

    public static func available(for kind: ClipboardKind) -> [Self] {
        switch kind {
        case .text: [.pasteOriginal, .pastePlainText]
        case .richText: [.pasteOriginal, .pastePlainText, .quickLook]
        case .link: [.pasteOriginal, .openLink, .pastePlainText]
        case .file: [.pasteOriginal, .pasteFilePath, .openFile, .revealInFinder, .quickLook]
        case .image: [.pasteOriginal, .quickLook]
        case .mixed: [.pasteOriginal, .pastePlainText, .quickLook]
        case .unknown: [.pasteOriginal, .quickLook]
        }
    }

    public var localizationKey: String {
        "contextAction.\(rawValue)"
    }

    public var symbolName: String {
        switch self {
        case .pasteOriginal: "arrow.down.doc"
        case .pastePlainText: "textformat"
        case .pasteFilePath: "point.topleft.down.to.point.bottomright.curvepath"
        case .openLink: "safari"
        case .openFile: "doc.badge.arrow.up"
        case .revealInFinder: "folder"
        case .quickLook: "eye"
        }
    }
}
```

Keep favorite, rename, and delete outside this enum because they are universal item-management actions.

- [ ] **Step 4: Implement safe system actions behind the integration service**

Extend `ItemIntegrationServing` with:

```swift
func availableContextActions(for item: ClipboardItem) -> [ItemContextAction]
func perform(_ action: ItemContextAction, for item: ClipboardItem) throws
```

`AppItemIntegrationService` loads stored payloads, extracts file URLs using `URL(dataRepresentation:relativeTo:)`, extracts non-file URLs from `public.url` or convertible plain text, verifies allowed schemes and local file existence, then calls `NSWorkspace.open` or `activateFileViewerSelecting`. Paste and Quick Look continue through existing AppModel paths rather than being duplicated in the service.

- [ ] **Step 5: Render dynamic buttons**

Replace `supportsPlainTextPaste` and the static preview row with action-driven rendering in `DetailActionStack`. File, link, image, rich-text, text, mixed, and unknown selections render only their matrix actions. Management actions remain a separate compact row. Add English and Chinese strings for Open Link, Open File, Show in Finder, Paste File, Paste Link, Paste Image/PDF, and operation failures.

- [ ] **Step 6: Verify GREEN and commit**

Run `swift run ClipFlowCoreTests` and `swift build --product ClipFlowApp`. Commit:

```bash
git add Sources/ClipFlowUI Sources/ClipFlowApp/AppItemIntegrationService.swift Tests/ClipFlowCoreTests
git commit -m "feat: add content-specific clipboard actions"
```

### Task 3: Explicit live application language

**Files:**
- Modify: `Sources/ClipFlowUI/Localization.swift`
- Modify: `Sources/ClipFlowUI/SettingsModel.swift`
- Modify: `Sources/ClipFlowUI/SettingsView.swift`
- Modify: `Sources/ClipFlowUI/ClipFlowRootView.swift`
- Modify: `Sources/ClipFlowApp/ClipFlowApp.swift`
- Modify: `Sources/ClipFlowUI/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ClipFlowUI/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Tests/ClipFlowCoreTests/AppearancePreferencesTests.swift`
- Modify: `Tests/ClipFlowCoreTests/SettingsModelTests.swift`

- [ ] **Step 1: Write failing language tests**

Add tests for stable values, persistence, explicit locale, and resource selection:

```swift
#expect(AppLanguage.allCases == [.system, .simplifiedChinese, .english])
#expect(AppLanguage.simplifiedChinese.localeIdentifier == "zh-Hans")
#expect(AppLanguage.english.localeIdentifier == "en")

model.appLanguage = .simplifiedChinese
model.save()
#expect(SettingsModel(store: store, permissions: permissions).appLanguage == .simplifiedChinese)
#expect(L10n.string("settings.title") == "设置")
```

- [ ] **Step 2: Run tests and verify RED**

Run `swift run ClipFlowCoreTests`; expect compile failure because `AppLanguage` and the setting do not exist.

- [ ] **Step 3: Implement thread-safe language override**

Add:

```swift
public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"
}
```

`L10n.configure(language:)` stores the explicit identifier behind `NSLock`. `L10n.string`, `locale`, date formatting, and byte formatting read the override. Debug acceptance environment locale remains the highest-priority input. `SettingsModel.appLanguage` configures L10n in `init` and `didSet`, and persists under `appLanguage`.

- [ ] **Step 4: Add the picker and live view identity**

Add a General settings picker labeled Language with self-language option names. Include `appLanguage` in `SettingsSnapshot`. Apply `.id(settings.appLanguage)` and `.environment(\.locale, L10n.locale)` to main and Settings roots so all nested strings are recomputed. Rebuild Settings window title and menu-bar menu titles when language changes.

- [ ] **Step 5: Verify GREEN and commit**

Run tests plus localization key parity. Commit:

```bash
git add Sources/ClipFlowUI Sources/ClipFlowApp/ClipFlowApp.swift Tests/ClipFlowCoreTests
git commit -m "feat: add live English and Chinese language switching"
```

### Task 4: Live settings application and retention enforcement

**Files:**
- Create: `Sources/ClipFlowApp/AppSettingsCoordinator.swift`
- Modify: `Sources/ClipFlowApp/AppPasteService.swift`
- Modify: `Sources/ClipFlowApp/ClipFlowApp.swift`
- Modify: `Sources/ClipFlowStorage/ClipboardRepository.swift`
- Modify: `Sources/ClipFlowSystem/LocalLogger.swift`
- Modify: `Sources/ClipFlowUI/SettingsModel.swift`
- Modify: `Sources/ClipFlowUI/SettingsView.swift`
- Modify: `Tests/ClipFlowCoreTests/PasteCoordinatorTests.swift`
- Modify: `Tests/ClipFlowCoreTests/ClipboardRepositoryTests.swift`
- Modify: `Tests/ClipFlowCoreTests/SettingsModelTests.swift`

- [ ] **Step 1: Write failing live-settings tests**

Test that the paste service can update its default mode, the repository threshold can be updated, and retention cleanup applies all budgets while preserving favorites:

```swift
await service.updateDefaultMode(.plainText)
#expect(await service.resolvedMode(for: "com.example") == .plainText)

repository.updateExternalPayloadThreshold(bytes: 16)
let largeCapture = try ClipboardNormalizer(
    maxRepresentationBytes: 1_000,
    maxCaptureBytes: 2_000
).normalize(RawClipboardCapture(
    sourceAppName: "Test",
    sourceBundleID: nil,
    items: [RawClipboardItem(representations: [
        .init(type: "public.data", data: Data(repeating: 7, count: 16))
    ])]
))
#expect(try repository.upsert(largeCapture).hasExternalPayload)

let deleted = try repository.applyRetention(policy, now: now)
#expect(deleted == [oldestNonFavoriteID])
#expect(try repository.item(id: favoriteID) != nil)
```

Add a pure settings-change plan test proving shortcut, status item, paste mode, threshold, retention, logger, and language changes are detected independently.

- [ ] **Step 2: Run tests and verify RED**

Run `swift run ClipFlowCoreTests`; expect missing-API failures.

- [ ] **Step 3: Implement mutable service settings**

Make `AppPasteService` store a mutable default mode inside its actor. Protect the repository threshold with its existing synchronization boundary and expose `updateExternalPayloadThreshold(bytes:)`. Add `retentionCandidates()` and `applyRetention(_:now:)` that call the existing `delete` path for every policy-selected ID.

- [ ] **Step 4: Implement AppSettingsCoordinator**

Create a main-actor coordinator with injected closures/services. Its `apply(previous:current:)` method:

```swift
if previous.shortcut != current.shortcut { try updateShortcut(current.shortcut) }
if previous.showStatusBarItem != current.showStatusBarItem || previous.appLanguage != current.appLanguage {
    updateStatusItem(current.showStatusBarItem)
}
if previous.defaultPasteMode != current.defaultPasteMode { await pasteService.updateDefaultMode(...) }
if previous.externalPayloadThresholdMB != current.externalPayloadThresholdMB { repository.updateExternalPayloadThreshold(...) }
if previous.retention != current.retention {
    try repository.applyRetention(current.retention.policy, now: Date())
}
if previous.debugLoggingEnabled != current.debugLoggingEnabled { await logger.setEnabled(...) }
```

Use a typed runtime snapshot:

```swift
struct RetentionSettings: Equatable, Sendable {
    let preference: RetentionPreference
    let maximumItemCount: Int
    let maximumStorageMB: Int

    var policy: RetentionPolicy {
        RetentionPolicy(
            maxAge: preference.maxAge,
            maxItemCount: maximumItemCount,
            maxBytes: maximumStorageMB * 1_048_576
        )
    }
}

struct AppSettingsRuntimeSnapshot: Equatable, Sendable {
    let shortcut: HotKeyShortcut
    let showStatusBarItem: Bool
    let appLanguage: AppLanguage
    let defaultPasteMode: PasteMode
    let externalPayloadThresholdMB: Int
    let retention: RetentionSettings
    let debugLoggingEnabled: Bool
}
```

Register it in `AppDelegate`, run retention at startup and after each successful upsert, and expose localized Settings errors. Shortcut changes must restore the previous shortcut if registration fails.

- [ ] **Step 5: Connect privacy-safe logging**

Create `ClipFlow.log` under application support. Log startup, capture kind/byte count, cleanup count, paste outcome, and settings-application errors without content, URLs, paths, clipboard payloads, or search text. The logger remains disabled unless the preference is enabled.

- [ ] **Step 6: Verify GREEN and commit**

Run all tests and Debug build. Commit:

```bash
git add Sources/ClipFlowApp Sources/ClipFlowStorage Sources/ClipFlowSystem/LocalLogger.swift Sources/ClipFlowUI/SettingsModel.swift Sources/ClipFlowUI/SettingsView.swift Tests/ClipFlowCoreTests
git commit -m "feat: apply settings live and enforce retention"
```

### Task 5: Honest Settings UI and errors

**Files:**
- Modify: `Sources/ClipFlowUI/SettingsModel.swift`
- Modify: `Sources/ClipFlowUI/SettingsView.swift`
- Modify: `Sources/ClipFlowApp/ClipFlowApp.swift`
- Modify: `Sources/ClipFlowUI/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ClipFlowUI/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Tests/ClipFlowCoreTests/SettingsModelTests.swift`
- Modify: `Tests/ClipFlowCoreTests/ClipboardKindPresentationTests.swift`

- [ ] **Step 1: Write failing Settings-surface tests**

Test that Settings snapshots no longer include `autoCheckUpdatesEnabled`, language is present, runtime error messages can be set and cleared, and every new visible key exists in English and Chinese.

- [ ] **Step 2: Run tests and verify RED**

Run `swift run ClipFlowCoreTests`; expect failures while the obsolete property and missing error/language fields remain.

- [ ] **Step 3: Remove misleading update UI and expose real status**

Remove the automatic-update row, visible localization keys, snapshot field, and active SettingsModel property. Keep backward-compatible stored data ignored. Add a localized error banner to the top of Settings. Login item and shortcut failures populate it; successful retry clears it.

Add a diagnostics row showing the local log path and a Reveal in Finder button that is disabled until the file exists.

- [ ] **Step 4: Verify Settings behavior and commit**

Run tests, build, and localization lint/parity. Commit:

```bash
git add Sources/ClipFlowUI Sources/ClipFlowApp/ClipFlowApp.swift Tests/ClipFlowCoreTests
git commit -m "fix: make every visible setting functional"
```

### Task 6: Product verification and local test launch

**Files:**
- Modify: `Sources/ClipFlowCore/DevelopmentDemoData.swift`
- Modify: `Tests/ClipFlowCoreTests/DevelopmentDemoDataTests.swift`
- Modify: `scripts/capture-visual-acceptance.sh`
- Modify: `docs/acceptance/clipflow-visual-redesign-checklist.md`

- [ ] **Step 1: Expand deterministic acceptance fixtures**

Seed Finder-style multi-representation file data and browser-style URL/title data. Add capture scenarios for Chinese Settings, file actions, link actions, image actions, and text actions.

- [ ] **Step 2: Run complete verification**

Run:

```bash
swift run ClipFlowCoreTests
swift build --product ClipFlowApp
swift build -c release --product ClipFlowApp
plutil -lint Sources/ClipFlowUI/Resources/en.lproj/Localizable.strings Sources/ClipFlowUI/Resources/zh-Hans.lproj/Localizable.strings
git diff --check
./scripts/capture-visual-acceptance.sh
```

Expected: zero test failures, both builds succeed, localization resources are valid with identical key sets, diff check is clean, and all required PNG captures are generated.

- [ ] **Step 3: Inspect visual captures**

Confirm English and Chinese Settings render without clipping, each selected content type exposes only its expected actions, file/link classification badges are correct, and compact layout remains usable.

- [ ] **Step 4: Commit acceptance updates**

```bash
git add Sources/ClipFlowCore/DevelopmentDemoData.swift Tests/ClipFlowCoreTests/DevelopmentDemoDataTests.swift scripts/capture-visual-acceptance.sh docs/acceptance/clipflow-visual-redesign-checklist.md
git commit -m "test: cover semantic actions and complete settings"
```

- [ ] **Step 5: Launch the verified Debug application**

Stop the prior Debug process, launch the newly built `.build/debug/ClipFlowApp`, confirm it remains running, and instruct the user to test file, link, image, text, Settings, and live language switching with `⌘⇧V`.
