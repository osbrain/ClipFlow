# ClipFlow Product Design

## Purpose

ClipFlow is a distributable, native macOS clipboard manager that reproduces the observable behavior of the installed Clipi application while using an independently written codebase, product name, bundle identifier, signing identity, update channel, and visual assets. It prioritizes keyboard speed, native window behavior, local privacy, recovery from failure, and maintainable automated tests.

The first supported release targets macOS 14 Sonoma and newer on Apple Silicon and Intel Macs. It is distributed outside the Mac App Store with Developer ID signing, Apple notarization, a DMG, and Sparkle 2 updates.

## Product Boundaries

ClipFlow is local-only. It has no account system, cloud synchronization, advertising, analytics, telemetry, or remote clipboard processing. Network access is used only for an explicitly configured Sparkle update feed. Browser automation is performed locally through Apple Events after user authorization.

The product does not copy Clipi source code, bundle identifiers, icons, signatures, private update endpoints, or private backend services. Feature and interaction equivalence is established from observable application behavior and macOS public APIs.

## User Experience

### Application Lifecycle

- ClipFlow runs as a menu bar application and can optionally launch at login.
- The primary global shortcut is Command-Shift-V. The user can choose from supported shortcut presets in Settings.
- Invoking the shortcut toggles a floating, resizable panel on the active display, restores its last valid size and location, and focuses search.
- Escape clears an active search first, then dismisses the panel. Clicking outside dismisses the panel unless a sheet, rename field, drag operation, or system picker is active.
- The panel remains usable across multiple displays, Spaces, full-screen applications, and after display topology changes.

### Main Panel

The main panel follows the observable Clipi information architecture:

- A category sidebar contains All, content kinds, Favorites, Browser Tabs when enabled, and user-created categories.
- A search field searches preview text, custom titles, normalized searchable text, application name, and browser-tab title or URL.
- A keyboard-navigable history list shows the content icon or thumbnail, preview, source application, relative time, favorite state, and category state.
- A detail pane presents the complete text or image preview and configurable metadata fields: source, type, created time, last-used time, file path, and default paste mode.
- Contextual actions include paste, paste as plain text, copy back to clipboard, favorite, rename, assign category, reveal a file, delete, and application-specific actions when enabled.
- Space opens Quick Look for supported image and file payloads. Return pastes the selected item. Command-Return copies without pasting.
- Dragging an item out writes the best macOS pasteboard representation. Dropping an item onto a category assigns it.

### Clipboard Capture and Paste

- Capture supports plain text, UTF-8 text, RTF, HTML, URLs, file URLs, PNG, TIFF, JPEG, WebP when decodable, PDF data, colors, and unknown custom pasteboard types within configured size limits.
- A pasteboard may contain multiple logical items and multiple representations per item; all accepted representations are preserved.
- Exact duplicates are identified by a canonical SHA-256 content hash and update recency instead of creating repeated rows.
- Capture records the frontmost source application's name and bundle identifier when available.
- ClipFlow ignores pasteboard changes it creates itself and pauses capture during sensitive internal transformations.
- Paste restores original representations by default. Per-target-application preferences can select original or plain-text paste.
- Automatic Command-V posting is available after Accessibility authorization. Without authorization, ClipFlow restores the pasteboard and shows a non-blocking instruction to paste manually.

### Organization and Retention

- Users can favorite, rename, delete, search, and assign items to multiple custom categories.
- Categories support create, inline rename, delete with confirmation, and drag-and-drop assignment.
- Retention policies include unlimited, one day, one week, one month, and a configurable maximum item count and byte budget.
- Cleanup never removes favorites. Cleanup transactions remove database rows and external payload files atomically from the user's perspective.
- Clear History supports excluding favorites and requires confirmation.

### Browser Tabs

- Browser tab management is disabled by default and can be enabled in Settings.
- Adapters support Safari, Google Chrome, and Microsoft Edge.
- ClipFlow reports each browser as not installed, not running, authorization required, or authorized.
- Authorized tabs appear as a searchable category with browser icon, title, URL, and window context.
- Selecting a tab activates the existing browser window and tab. If the tab no longer exists, the cache is refreshed and the user receives a non-blocking error.
- Denied or unavailable browser automation never blocks clipboard capture, search, or paste.

### Settings and Onboarding

- First launch explains local storage, clipboard monitoring, Accessibility, browser automation, login launch, and updates before requesting optional permissions.
- Settings cover shortcut, launch at login, menu bar visibility, retention, storage usage, external-payload threshold, default and per-app paste modes, detail fields, browser tabs, optional application actions, update behavior, debug logging, data export, data import, and reset.
- Permission screens deep-link to the appropriate System Settings pane and continuously refresh status when the application becomes active.
- Debug logs are off by default, rotate locally, redact clipboard contents, and can be revealed or exported by the user.

### Updates and Distribution

- Sparkle 2 checks a signed HTTPS appcast. Automatic checks are user-configurable.
- Updates are verified with Sparkle's EdDSA signature and Apple code signing before installation.
- Failure to check, download, verify, or install an update leaves the current application usable and reports a recoverable status.
- Release output includes a signed and notarized universal application and DMG.

## Architecture

### Targets

- `ClipFlowApp`: SwiftUI application target with AppKit delegates, status item, floating panel, Settings window, permission routing, Sparkle wiring, and dependency composition.
- `ClipFlowCore`: Swift Package containing domain models, clipboard normalization, hashing, search queries, retention rules, import/export models, and protocols for system services.
- `ClipFlowStorage`: Swift Package target containing SQLCipher connection management, schema migrations, repositories, encrypted external-payload storage, backup, and recovery.
- `ClipFlowSystem`: Swift Package target containing NSPasteboard capture/writeback, Accessibility paste posting, frontmost-application lookup, global hotkeys, login items, Keychain, Quick Look, browser Apple Events adapters, and local logging.
- `ClipFlowCoreTests`, `ClipFlowStorageTests`, and `ClipFlowSystemTests`: deterministic unit and integration tests. UI tests cover launch, search, navigation, category management, settings, and permission-state presentation.

### State and Data Flow

1. `PasteboardMonitor` observes `NSPasteboard.general.changeCount` on a low-cost timer.
2. `ClipboardCaptureService` snapshots every item and accepted representation, enforces per-representation and total limits, determines the source application, and creates a canonical capture.
3. `ClipboardRepository` writes metadata and payloads in one SQLCipher transaction. Payloads above the configured threshold are encrypted with AES-GCM and stored in the application support payload directory; the database stores the encrypted file reference.
4. `HistoryController` receives repository change notifications, runs the active search/filter query, and publishes immutable view state to SwiftUI.
5. `PasteCoordinator` loads and validates all payloads, writes them to NSPasteboard, marks the item used, closes the panel, restores the target application, and posts Command-V when authorized.

### Storage Model

The encrypted SQLCipher database contains:

- `schema_migrations(version, applied_at)`
- `clipboard_items(id, created_at, updated_at, app_name, bundle_id, kind, preview_text, search_text, byte_size, content_hash, is_favorite, last_used_at, custom_title)`
- `pasteboard_payloads(item_id, item_index, type, inline_data, external_file_name, byte_size, sha256)`
- `clip_categories(id, name, created_at, sort_order)`
- `item_categories(item_id, category_id, created_at)`
- `app_paste_preferences(bundle_id, paste_mode)`

The SQLCipher key is a random 256-bit value created on first launch and stored as a non-synchronizing Keychain item. Database opening verifies the schema and integrity before capture begins. Backups are encrypted copies and never contain a plaintext key.

### Window and Input Model

AppKit owns the main `NSPanel`, event routing, global Carbon hotkey, activation behavior, panel geometry, and menu bar item. SwiftUI owns the panel content and settings content. The panel controller explicitly distinguishes search focus, text editing, list navigation, detail interaction, sheets, drag sessions, and dismissed state so Escape and arrow keys remain predictable.

### Error Handling and Recovery

- Malformed or unsupported pasteboard representations are skipped individually; valid representations from the same capture are retained.
- Storage writes are transactional. A failed capture leaves no partial history item or orphaned external payload.
- External payload reads verify size and SHA-256 before use. Missing or corrupt payloads show an unavailable state and can be deleted without crashing.
- Database open failure triggers an integrity check, then recovery from the latest valid encrypted backup. The original file is preserved for manual support.
- Keychain denial stops storage access and presents a recoverable local error; ClipFlow never silently creates a second database with a different key.
- Browser, Accessibility, login-item, Quick Look, and update errors are isolated behind service protocols and cannot stop core clipboard monitoring.
- All user-facing errors describe the failed action, whether data was changed, and the next recovery action.

## Security and Privacy

- SQLCipher encrypts the complete database, including previews and indexes.
- Large external payloads are independently AES-GCM encrypted with versioned file headers and per-file nonces.
- Key material never appears in preferences, logs, crash text, exports, or command-line arguments.
- Clipboard payload content is never logged. Debug logging uses identifiers, sizes, types, timing, and redacted error descriptions.
- Export requires an explicit destination and produces either an encrypted ClipFlow archive or a user-confirmed plaintext interoperability export.
- Network code is limited to the configured Sparkle updater. Automated tests assert that core and storage packages do not link networking frameworks.

## Testing and Acceptance

Development follows test-driven development for domain, storage, and service behavior.

- Unit tests cover normalization, hashing, deduplication, search ranking, retention, paste-mode resolution, keyboard state transitions, browser status mapping, and migration decisions.
- Storage integration tests run against temporary SQLCipher databases and cover transactions, migrations, concurrent reads, encrypted backups, external payload encryption, corruption detection, and recovery.
- Pasteboard integration tests use isolated named pasteboards where possible and a controlled manual suite for general-pasteboard behaviors macOS does not virtualize.
- UI tests cover onboarding, main panel invocation through an injectable hotkey service, search, keyboard navigation, favorites, categories, detail configuration, settings persistence, and error banners.
- Performance tests use 10,000, 100,000, and 500,000 metadata records. The 100,000-item acceptance target is panel presentation under 150 ms after process warm-up and typical indexed search results under 100 ms on the development Mac.
- Memory tests verify lazy payload loading and bounded thumbnail caches. Large payloads are never fully loaded into history-list rows.
- Release verification builds a universal Release archive, runs all tests, validates hardened runtime and entitlements, signs nested code, notarizes the DMG, verifies the Sparkle appcast signature, and installs the update over the previous release in a clean macOS user account.

## Completion Criteria

ClipFlow is complete when every feature above is implemented, automated tests pass, the main Clipi workflows have recorded side-by-side acceptance checks, Accessibility and browser-denial paths remain usable, an encrypted database survives migration and recovery testing, and a signed/notarized DMG can update from the preceding signed release without losing history.
