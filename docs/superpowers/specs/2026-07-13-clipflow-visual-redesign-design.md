# ClipFlow Visual Redesign Design

**Date:** 2026-07-13  
**Status:** Approved direction, pending written-spec review  
**Scope:** Main panel, history rows, icon and thumbnail system, detail preview, settings, appearance, localization, accessibility, and visual acceptance.

## 1. Objective

Redesign ClipFlow into a polished native macOS clipboard manager with the information density and visual clarity demonstrated by Clipi, while retaining an independently designed ClipFlow identity and the existing encrypted local architecture.

The redesign must improve more than color and spacing. It must introduce a coherent visual component system, richer content-aware icons, real source-application icons, payload thumbnails, a more useful detail panel, and a complete card-based Settings experience.

## 2. Product Principles

- Preserve native macOS behavior, keyboard operation, accessibility, Quick Look, drag-out, and system application icons.
- Reuse the existing encrypted repository and system-service boundaries. UI work must not create a second clipboard or storage path.
- Do not copy Clipi artwork, app icons, brand assets, exact colors, or proprietary resources.
- Use Clipi's observable information architecture as a benchmark: compact branding, powerful search, horizontal filtering, dense history rows, rich previews, and grouped settings.
- Keep clipboard contents local. Thumbnail and icon generation must not use network services.
- Avoid eager decryption of every history payload. Only visible or selected items may request payload-backed thumbnails.

## 3. Considered Approaches

### 3.1 Direct visual reproduction

Reproduce the two-pane dark glass layout and controls as closely as possible.

This gives the fastest visual parity but risks looking like a reskin and makes future ClipFlow identity work harder.

### 3.2 Refined native sidebar

Keep the existing three-column sidebar, list, and detail layout and improve its colors and icons.

This minimizes code changes but retains the current weak hierarchy and does not match the workflow density requested by the user.

### 3.3 Selected: adaptive Clipi-inspired layout with independent identity

Adopt the effective structure of the reference application while building original ClipFlow components, colors, typography, icons, and responsive rules.

This approach gives the requested usability and visual quality without copying product assets or locking ClipFlow into an exact replica.

## 4. Main Panel Information Architecture

### 4.1 Wide layout

At widths of 900 points or greater, the window uses two primary columns:

- History workspace: approximately 64 percent of available width.
- Preview and detail workspace: approximately 36 percent.

The existing permanent type sidebar is removed from the wide default layout. Categories and primary filters move to a horizontal chip row above the history list.

### 4.2 Compact layout

Between 760 and 899 points:

- The history list keeps a minimum useful width.
- The detail pane becomes narrower and hides secondary metadata labels before truncating content.
- Category chips scroll horizontally.
- Action labels may collapse to familiar icons with tooltips.

The panel never clips controls or places text under action buttons.

### 4.3 Header

The top header contains:

- Original ClipFlow brand icon and name.
- A concise privacy subtitle.
- Context for the selected item's source application when an item is selected.
- A prominent Settings button using a gear icon.
- Optional compact status indicators for permission or update problems.

### 4.4 Search

The search field sits below the header and spans the history workspace. Its placeholder communicates searchable dimensions: content, source application, links, files, and browser tabs.

Search behavior remains debounced and keyboard-first. The field uses a dark rounded material with a visible focus ring and clear button.

### 4.5 Filter and category chips

The chip row contains:

- All items.
- Favorites.
- Text, rich text, images, files, and links.
- Browser tabs when enabled.
- User categories.
- A plus button for creating a category.

Each chip has an icon, label, selected state, hover state, keyboard focus state, and accessible selected value. User categories support rename, delete, and drag assignment through their existing model operations.

## 5. History Row Design

Each row is a rounded card with a subtle material fill and content-sensitive accent. It contains:

- A 40-44 point leading visual.
- A small source application icon and source name.
- Relative or absolute capture time.
- A one- or two-line content title.
- A content-kind label and icon.
- Favorite state when applicable.

Selection uses an accent outline and stronger material fill instead of changing the entire row to an opaque system selection color.

### 5.1 Leading visual priority

The leading visual follows this order:

1. Generated thumbnail for image and PDF payloads.
2. System file icon for existing file URLs.
3. Rich content badge for HTML and RTF.
4. Link favicon is not fetched from the network; use a local link badge or source-app icon.
5. Content-kind badge as the final fallback.

The small source icon is always independent from the leading content visual and is obtained from `NSWorkspace` using the captured bundle identifier.

## 6. Icon and Thumbnail Architecture

### 6.1 `ApplicationIconProviding`

Resolves a bundle identifier to the installed application's `NSImage`. It returns a deterministic fallback symbol when an application has been uninstalled or the bundle identifier is absent.

Application icons are cached by bundle identifier and requested on the main actor only when AppKit requires it.

### 6.2 `ClipboardVisualProviding`

Produces a lightweight visual descriptor for a clipboard item:

- Application icon.
- Kind symbol and tint.
- Optional thumbnail.
- Optional system file icon.

Metadata-only visuals are returned immediately. Payload-backed thumbnails load asynchronously for visible or selected rows.

### 6.3 `ClipboardThumbnailService`

Generates bounded thumbnails from decrypted payloads:

- Image payloads use `CGImageSourceCreateThumbnailAtIndex` with a maximum pixel size.
- PDFs use Quick Look Thumbnailing when available, with a local fallback.
- Existing files use system icons and do not copy file contents.
- Unsupported or corrupt data returns a kind fallback without failing the list.

The service uses `NSCache` with a cost based on pixel dimensions. Cache keys include item ID and content hash. Obsolete thumbnail tasks are cancellable.

### 6.4 Visual component boundaries

Reusable SwiftUI components include:

- `ClipFlowAppIconView`
- `ClipboardKindBadge`
- `ClipboardThumbnailView`
- `SourceApplicationLabel`
- `MetadataCard`
- `FilterChip`
- `GlassSection`
- `GlassRow`

These components own appearance only and do not access repositories directly.

## 7. Preview and Detail Pane

The detail pane is divided into:

1. Selected-item header with source icon, source name, time, kind badge, and favorite state.
2. Preview card.
3. Metadata cards.
4. Primary and secondary actions.

### 7.1 Preview behavior

- Images render an in-panel aspect-fit preview and retain the existing Quick Look expansion action.
- Text and rich text use selectable content with bounded rendering.
- File items show the file icon, name, path, and availability state.
- Links show a local link card without remote page fetching.
- Unsupported or failed previews display a useful fallback and never disable paste.

### 7.2 Metadata cards

Cards display only fields enabled in Settings. Supported fields include:

- Kind.
- Source application.
- Created time.
- Last-used time.
- Size.
- Original formatting availability.

Each card uses a meaningful icon rather than a text-only grid.

### 7.3 Actions

The primary paste button remains visually dominant. Secondary actions include Quick Look, plain-text paste when compatible, favorite, rename, delete, copy file path, and enabled application actions.

Buttons use label-plus-icon when space permits. Compact mode may use familiar icons with tooltips and accessibility labels.

## 8. Visual Language

ClipFlow uses an original blue-green and indigo accent system. The design must not copy Clipi's exact palette.

### 8.1 Materials

- Window background: layered native material with a restrained dark overlay.
- Cards: thin material with a low-contrast border.
- Selected cards and chips: accent-tinted fill plus a one-point accent outline.
- Error banners: semantic red with readable contrast.

### 8.2 Shape and spacing

- Primary cards: 12-point corner radius.
- Controls and chips: 8-10 point corner radius.
- Row height: 74 points in comfortable density and 62 points in compact density.
- Consistent spacing tokens: 4, 8, 12, 16, 24.

### 8.3 Appearance modes

Settings provide:

- Follow System.
- Light.
- Dark.

The default remains Follow System. Both color schemes must preserve contrast and material readability.

## 9. Settings Experience

The current tabbed `Form` is replaced with a scrollable card-based settings window. A compact header contains the Settings icon, title, and subtitle. The body contains grouped `GlassSection` cards.

### 9.1 General

- Global panel shortcut.
- Default paste mode.
- Menu bar visibility.
- List density.
- Appearance mode.
- Follow-system language behavior.

### 9.2 Retention and storage

- Segmented retention choices: one day, one week, one month, unlimited.
- Maximum item count.
- Maximum storage.
- External payload threshold.
- Current item count and storage usage when repository statistics are available.

Favorites continue to follow the existing retention exemption. Category membership does not silently change retention behavior as part of this visual redesign.

### 9.3 Permissions and integrations

- Accessibility status with a Settings deep link.
- Browser tab management.
- Feishu action.
- Doubao action.
- Permission states use semantic icons and explanatory help text.

### 9.4 Startup and updates

- Launch at login.
- Automatic update checks.
- Manual update check once the update controller is integrated.

### 9.5 Detail fields

- Source application.
- Content type.
- Created time.
- Last-used time.
- File size and formatting availability where applicable.

### 9.6 Data and diagnostics

- Export encrypted backup.
- Import encrypted backup.
- Reveal or export redacted logs.
- Reset local data with destructive confirmation.

Buttons that depend on unfinished backup or update infrastructure remain absent until the underlying service is complete. The redesign must not ship decorative controls that do nothing.

## 10. Localization

ClipFlow follows the macOS language automatically and ships complete Simplified Chinese and English UI strings.

- User-facing strings move out of view implementations into package resources.
- Chinese is not treated as an English fallback or partial translation.
- Dynamic values use locale-aware date, byte-size, count, and relative-time formatting.
- Accessibility labels and help text are localized with the visible UI.

## 11. Accessibility and Keyboard Behavior

- Every icon-only control has an accessibility label and tooltip.
- Selected chips expose their selected state.
- App icons and thumbnails do not repeat decorative descriptions when adjacent text already identifies the item.
- Text respects system font scaling where macOS supports it.
- Contrast meets readable native control expectations in light and dark modes.
- Return pastes, Space opens Quick Look when the search field is not editing, Escape clears search before dismissing, and arrow navigation remains deterministic.

## 12. Data Flow

1. `AppModel` loads lightweight `ClipboardItem` metadata.
2. Rows immediately render kind and application-icon fallbacks.
3. Visible rows request optional visual descriptors from the visual provider.
4. The provider loads payloads only when a thumbnail requires them.
5. Generated thumbnails enter the bounded cache and update only the corresponding row.
6. Selecting an item requests a larger preview independently from list-thumbnail work.
7. Paste, drag, Quick Look, browser automation, and application actions continue through their existing service interfaces.

## 13. Failure Handling

- Missing applications use a neutral application fallback icon.
- Missing files show an unavailable-file state but preserve stored metadata.
- Corrupt or unsupported image data falls back to a kind badge.
- Thumbnail failures are isolated and never become global history errors.
- Settings persistence failures retain the current in-memory selection and display a non-blocking error once the settings store supports throwing operations.
- Permission denial shows actionable state without blocking clipboard capture or search.

## 14. Performance Requirements

- Metadata-only history rows must not decrypt payloads.
- Thumbnail generation is bounded to visible or selected items.
- Thumbnail pixel dimensions are capped and cached by memory cost.
- Scrolling must not synchronously read large external payload files on the main actor.
- Search and selection updates must cancel obsolete visual work.
- Warm panel presentation target remains below 150 ms when measured in the final performance milestone.

## 15. Testing Strategy

### 15.1 Unit tests

- Kind-to-symbol and tint mapping.
- Application-icon fallback selection.
- Thumbnail request eligibility and cache key construction.
- Retention and appearance-setting persistence.
- Localized string availability for English and Simplified Chinese.
- Detail field visibility.

### 15.2 Integration tests

- Image payload produces a bounded thumbnail.
- Invalid image payload falls back without throwing into `AppModel`.
- Existing file URL produces the correct system icon path.
- Settings changes persist and affect the main panel without restart.

### 15.3 Native visual acceptance

Capture and inspect at minimum:

- Populated dark main panel.
- Populated light main panel.
- Image, text, file, and link selections.
- Empty history and no-search-results states.
- Browser tab category and permission states.
- Simplified Chinese settings window.
- English settings window.
- Compact and wide panel sizes.

Acceptance checks include clipping, alignment, icon quality, contrast, hover and selected states, localization expansion, and consistent card spacing.

## 16. Delivery Sequence

1. Localization and appearance settings foundation.
2. Reusable visual tokens and glass components.
3. Application icon and kind badge system.
4. Thumbnail service and row redesign.
5. Main panel header, search, filter chips, and adaptive two-pane layout.
6. Preview and detail cards.
7. Card-based settings window.
8. Keyboard, accessibility, and native visual acceptance.

## 17. Non-Goals

- Copying Clipi brand assets, colors, source code, or application icon.
- Adding cloud synchronization or remote thumbnail services.
- Replacing SQLCipher, payload encryption, or the existing clipboard capture pipeline.
- Shipping backup, update, or reset buttons before their underlying services are implemented.

## 18. Acceptance Criteria

The redesign is accepted when:

- The main panel uses the approved adaptive two-pane structure and horizontal filter chips.
- Image, file, rich-text, link, and source-application visuals have clear, distinct icon treatment.
- Images and supported documents show cached local thumbnails without eager payload loading.
- The detail pane provides content-aware previews and icon-based metadata cards.
- Settings use a coherent card-based scroll layout and expose all currently functional options.
- Simplified Chinese and English are complete and follow the system language.
- Light and dark appearance modes are usable and persist correctly.
- Existing clipboard capture, encrypted persistence, search, paste, browser tabs, Quick Look, drag, and application actions remain functional.
- Automated tests, application build, and the required native visual acceptance matrix pass.
