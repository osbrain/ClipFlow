# ClipFlow Semantic Classification, Context Actions, and Complete Settings Design

**Date:** 2026-07-14
**Status:** Approved product direction
**Scope:** Clipboard classification, item-specific detail actions, settings runtime behavior, explicit application language, and regression coverage.

## 1. Objective

Make ClipFlow classify real macOS clipboard objects by their semantic content instead of treating every pasteboard representation as an independent content type. The detail pane must expose actions that are useful for the selected item, and every visible setting must either work immediately or clearly report why it could not be applied. Users must be able to switch between the system language, Simplified Chinese, and English from inside ClipFlow.

## 2. Current Problems and Root Causes

### 2.1 Clipboard classification

Finder, browsers, and rich editors commonly place several representations on one `NSPasteboardItem`. A copied file may contain `public.file-url`, plain text, and Finder-private metadata. A copied link may contain `public.url`, a title as plain text, and browser-private metadata. The current normalizer maps every representation to a kind and returns `.mixed` whenever those mapped kinds differ, so companion formats incorrectly change the semantic kind.

The current classifier also recognizes only a small list of exact UTI strings. It misses compatible text, URL, image, and file representations, and it cannot infer that a plain-text HTTP or HTTPS URL is a link.

### 2.2 Detail actions

The detail pane currently uses one mostly static action stack. Files only receive a differently worded plain-text paste button, while links cannot open in the default browser and files cannot open or reveal themselves in Finder. The action layout is therefore not aligned with the selected content.

### 2.3 Settings completeness

Some preferences are fully live, while others are only persisted or are not connected to a runtime service:

- Appearance, density, and detail-field visibility are live.
- Shortcut, menu-bar visibility, default paste mode, and the external-payload threshold are read primarily at launch.
- Retention age, item count, and storage budgets are not enforced by the repository.
- Automatic updates have no update source or updater implementation.
- The local logger exists but the debug-logging preference is not connected to it.
- Login-item errors are discarded.
- Localization follows the process language and has no in-app language preference.

## 3. Semantic Clipboard Classification

### 3.1 Per-item classification

The normalizer will classify each pasteboard item as one semantic object. It will use `UniformTypeIdentifiers.UTType` conformance where available and exact legacy identifiers as compatibility fallbacks.

Within one pasteboard item, semantic priority is:

1. File URL or Finder file-list representation → `.file`.
2. Non-file URL representation → `.link`.
3. Image or PDF representation → `.image`.
4. Rich text or HTML representation → `.richText`.
5. Plain text representation → `.text`, except a single normalized HTTP, HTTPS, or mail URL becomes `.link`, and an explicit `file://` URL becomes `.file`.
6. No recognized semantic representation → `.unknown`.

Private metadata and companion representations do not create `.mixed` by themselves.

### 3.2 Capture aggregation

After classifying each pasteboard item, the capture kind is:

- The shared kind when every item has the same semantic kind, including multi-file selections.
- `.mixed` only when the capture genuinely contains different semantic objects.
- `.unknown` only when no item has a recognized semantic type.

All accepted representations remain encrypted and stored so original-format paste remains lossless. Classification changes metadata only; it does not discard compatible payloads.

### 3.3 Preview selection

Preview text remains human-readable, but content-specific payloads are preferred when needed:

- Files derive a decoded standardized path from a file-URL or Finder file-list payload.
- Links prefer the URL payload while retaining a title in search text when available.
- Rich text and text use a decoded textual representation.
- Images use their existing thumbnail pipeline.

Existing records are not silently rewritten. New captures receive corrected classification, and an explicit repository reclassification pass will update existing records from their stored payload metadata without changing IDs, favorites, categories, titles, timestamps, or content hashes.

## 4. Typed Context Actions

### 4.1 Action model

A pure `ItemContextAction` model will describe supported actions, labels, symbols, keyboard hints, and presentation priority. Availability is derived from the selected item kind and verified payloads. UI code will render the model instead of embedding kind switches directly in button layout.

System operations remain behind `ItemIntegrationServing` so they are testable without opening applications during unit tests.

### 4.2 Action matrix

| Kind | Primary action | Context actions |
| --- | --- | --- |
| Text | Paste | Paste as Plain Text; enabled Feishu/Doubao actions |
| Rich text | Paste with Original Formatting | Paste as Plain Text; Quick Look when materialization succeeds; enabled application actions |
| Link | Paste Link | Open in Default Browser; Paste as Plain Text; enabled application actions |
| File | Paste File | Paste File Path; Open File; Show in Finder; Quick Look |
| Image/PDF | Paste Image or PDF | Quick Look; enabled compatible application actions |
| Mixed | Paste Original Content | Paste as Plain Text when convertible; Quick Look when materialization succeeds |
| Unknown | Paste Original Content | Quick Look when materialization succeeds |

Favorite, rename, and delete remain universal management actions and stay visually separated from content actions.

### 4.3 File and link safety

- File actions resolve URLs from stored payloads, not from display text.
- `Open File` is enabled only for an existing local file URL.
- `Show in Finder` uses `NSWorkspace.activateFileViewerSelecting` and is enabled only for an existing path.
- `Open in Default Browser` accepts only normalized non-file URLs with an allowed URL scheme.
- Failed operations produce localized, visible errors and never delete or mutate the history item.

## 5. Complete Runtime Settings

### 5.1 Runtime coordinator

An application-level settings coordinator will apply persisted changes to active services. It will be invoked after a validated settings snapshot is saved.

It will:

- Re-register the global shortcut and restore the previous registration if the new shortcut fails.
- Add or remove the menu-bar item immediately and rebuild localized menu titles.
- Update the default paste mode in `AppPasteService` immediately.
- Update the repository external-payload threshold for future payloads.
- Run retention cleanup after retention, item-count, or storage-budget changes.
- Enable or disable the local logger immediately.
- Refresh the Settings error banner when login-item or shortcut changes fail.

Browser-tab visibility, appearance, density, application actions, and detail fields continue to update through the shared observable settings model.

### 5.2 Retention enforcement

The repository will expose retention candidates and a cleanup operation based on the existing `RetentionPolicy` type. Cleanup runs:

- After a successful clipboard upsert.
- After retention-related settings change.
- Once during application startup.

Favorites are never automatically removed. The maximum item count and maximum storage size are both enforced after age-based removal. External payload files are deleted through the existing repository deletion path.

### 5.3 Honest settings surface

The automatic-update toggle will be removed until a signed distribution build has a real update feed and updater implementation. A visible but nonfunctional switch is not acceptable product behavior.

Debug logging will remain because it can be connected to the existing privacy-filtered local logger. The settings page will show the log location and an action to reveal it in Finder after the first log file exists.

Login-at-launch remains available, but failures are displayed in a localized Settings error banner instead of being silently ignored.

## 6. Explicit Application Language

### 6.1 Preference

`AppLanguage` has three stable persisted values:

- `system`
- `zh-Hans`
- `en`

The default is `system`. The language picker appears in General settings beside appearance and density.

### 6.2 Live application

Changing the preference updates the main panel, Settings window, onboarding content, error messages, date formatting, byte formatting, accessibility labels, status-menu titles, and Settings window title without requiring application restart.

`L10n` will use a thread-safe language override configured by `SettingsModel`. Root views receive a language identity and locale so SwiftUI recomputes all localized content. Debug visual-acceptance locale overrides remain deterministic and take precedence only in acceptance mode.

English and Simplified Chinese resource files must retain identical key sets. Language names are displayed in their own language: `跟随系统`, `简体中文`, and `English`.

## 7. Settings Validation and Errors

- Numeric settings are clamped before persistence and application.
- Shortcut registration, login-item registration, file actions, link opening, cleanup, and logger setup return typed failures.
- User-facing failures use localized messages and remain visible until the relevant operation succeeds or the user dismisses them.
- Settings changes that fail do not silently claim success; reversible settings restore their previous working value.

## 8. Testing and Acceptance

Automated coverage will include:

- Finder-style file payloads with file URL, plain text, and private metadata classify as `.file`.
- Browser-style URL payloads with URL, title text, and private metadata classify as `.link`.
- Plain HTTP/HTTPS URL text classifies as `.link`; ordinary text remains `.text`.
- Multi-file captures remain `.file`; genuinely heterogeneous captures become `.mixed`.
- Existing records can be reclassified without losing identity or user metadata.
- Every clipboard kind maps to the exact expected context-action set.
- Invalid or missing file and URL payloads disable or reject unsafe actions.
- Language defaults, persistence, locale selection, and English/Chinese resource parity.
- Shortcut, status item, paste mode, logger, threshold, and retention settings invoke their runtime services.
- Retention preserves favorites and deletes external payload files through repository deletion.
- Removed automatic-update UI has no remaining visible localization keys or stale Settings snapshot field.

Final verification will run the complete core test executable, Debug and Release builds, localization lint/parity, `git diff --check`, and visual captures for English and Simplified Chinese Settings plus representative file, link, image, and text detail actions.

## 9. Distribution Boundary

This work completes application behavior available in the current native Swift project. Universal archive creation, Developer ID signing, notarization, and a production update feed still require the complete Xcode/distribution environment and are not represented as finished by any Settings control.
