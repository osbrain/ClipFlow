# ClipFlow Visual Redesign Acceptance Checklist

Record evidence in the final column and select exactly one of Pass or Fail for every row. The capture batch writes ignored PNGs to `artifacts/visual-acceptance/`; interactive rows still require a manual pass in the Debug app.

| Area | Acceptance criterion | Pass | Fail | Evidence / notes |
| --- | --- | --- | --- | --- |
| Safe-mode isolation | Before launch, the executable contains the exact Debug-only static marker; it then passes the runtime probe, and every scenario confirms its unique ready token while using isolated defaults, storage, browser data, and disabled clipboard monitoring. | [x] | [ ] | All 11 scenarios passed the static marker, runtime probe, and unique ready-token checks. |
| Wide layout | `dark-zh-wide.png` and `light-en-wide.png` show the full history, detail pane, header, and actions without clipping or overlap. | [x] | [ ] | Both 1000 × 680 captures inspected. |
| Compact layout | `light-en-compact.png` remains usable at 800 × 520 with no truncated primary controls or inaccessible content. | [x] | [ ] | 800 × 520 capture inspected; panes remain scrollable. |
| Dark appearance | Dark materials, text, dividers, selection, and controls maintain legible contrast in `dark-zh-wide.png`. | [x] | [ ] | Dark main and Settings captures inspected. |
| Light appearance | Light materials, text, dividers, selection, and controls maintain legible contrast in the English captures. | [x] | [ ] | English main, Settings, action, and Quick Look captures inspected. |
| Chinese localization | The Chinese wide capture uses Chinese UI copy and has no missing translations, placeholder keys, or clipped labels. | [x] | [ ] | `dark-zh-wide.png` inspected; localization key parity also passed. |
| English localization | The English captures use natural English copy and have no missing translations, placeholder keys, or clipped labels. | [x] | [ ] | All English captures inspected; long action labels wrap without truncation. |
| Chinese Settings | `dark-zh-settings.png` shows the complete Settings surface in Simplified Chinese with no clipped labels or untranslated keys. | [x] | [ ] | Chinese title, sections, controls, and retention labels inspected. |
| Source and kind icons | Every seeded row shows its source-application icon and the correct text, rich-text, image, file, or link kind badge. | [x] | [ ] | Five seeded rows inspected across action captures. |
| Semantic Finder and browser classification | The Finder multi-representation fixture remains File and the Safari URL/title/source fixture remains Link. | [x] | [ ] | File and Link badges plus dedicated action sets visible in captures. |
| Image thumbnail | The Preview PNG fixture renders a bounded image thumbnail without distortion, blank output, or layout shift. | [x] | [ ] | Main image detail and Quick Look captures inspected. |
| File thumbnail | The Finder fixture shows the system file icon/thumbnail for the caller-created local demo file. | [x] | [ ] | Finder row and detail preview inspected. |
| Selection state | The selected row has a clear outline/background treatment in both light and dark appearances. | [x] | [ ] | Selected outline visible across captures. |
| Hover state | Moving the pointer across rows and icon buttons produces a visible, stable hover treatment without flicker. | [ ] | [ ] | |
| Search | Typing a query filters the seeded fixtures, preserves focus, and exposes a clear empty state when nothing matches. | [ ] | [ ] | |
| Filter chips | Kind/favorite filter chips show selected state, combine correctly with search, and remain keyboard operable. | [ ] | [ ] | |
| Detail cards | Selecting each fixture updates preview, metadata, source, size, and content cards without stale values. | [x] | [ ] | Text, image, file, and link detail captures inspected. |
| Primary paste action | The primary paste action is visually dominant, labeled, keyboard reachable, and disabled only when appropriate. | [x] | [ ] | Prominent type-specific primary buttons visible in all action captures. |
| Type-specific actions | `light-en-file-actions.png`, `light-en-link-actions.png`, `light-en-image-actions.png`, and `light-en-text-actions.png` expose only the correct actions for each selected kind. | [x] | [ ] | File actions show path/open/Finder/Quick Look; link and text labels are complete. |
| Settings layout | `light-en-settings.png` shows consistent section spacing, aligned labels/controls, and no clipping in the fixed 700 × 700 content area. | [x] | [ ] | English Settings capture inspected at the fixed rectangular size. |
| Settings completeness | Language, shortcut, menu bar, paste mode, retention, storage, launch-at-login, detail fields, integrations, and diagnostics are functional; no automatic-update control is shown. | [x] | [ ] | UI inspected; runtime application and legacy-setting behavior covered by tests. |
| Browser empty state | `light-en-browser-empty.png` uses the deterministic empty service (never live browser state) and shows the intended explanation and recovery/action affordance. | [x] | [ ] | Deterministic empty capture completed successfully. |
| Browser populated/error states | With browser tabs available or automation denied, populated and error states remain readable and actionable. | [ ] | [ ] | |
| Quick Look | `light-en-quick-look.png` comes from the PID-owned secondary high-layer preview window, never the main or Settings window, and visibly shows the seeded `public.png` fixture. | [x] | [ ] | PID-owned layer-8 QuickLookUI panel captured at 520 × 384. |
| Keyboard navigation | Tab, Shift-Tab, arrow keys, Return, Escape, search shortcut, and Settings shortcut move focus or act as documented. | [ ] | [ ] | |
| Search focus isolation | After Tab or Shift-Tab leaves search, Space, Return, and arrow keys do not trigger history-list commands unless a history or browser row explicitly owns focus. | [ ] | [ ] | |
| Native control activation | Focused filter chips, detail buttons, and other controls retain native Space and Return activation without panel-level command interception. | [ ] | [ ] | |
| Row accessibility semantics | A focused history or browser row exposes button and selected VoiceOver semantics, announces its meaningful label, and activates from the documented keyboard command. | [ ] | [ ] | |
| Accessibility | VoiceOver announces meaningful labels for icon-only controls, rows, chips, thumbnails, primary actions, and window landmarks. | [ ] | [ ] | |

## Required follow-up outside this batch

- Run the full UI-test matrix from a complete Xcode installation; the command-line Swift toolchain does not replace native UI automation.
- Build and validate a Universal app, then complete signing and notarization checks with the intended distribution identity.
- Review any pre-existing linker warnings separately; they are not evidence of a regression in the visual redesign batch unless the warning set changes.
- Verify hover, keyboard focus, VoiceOver order/labels, populated browser automation, and paste behavior interactively because static screenshots cannot establish them.
