# ClipFlow Visual Redesign Acceptance Checklist

Record evidence in the final column and select exactly one of Pass or Fail for every row. The capture batch writes ignored PNGs to `artifacts/visual-acceptance/`; interactive rows still require a manual pass in the Debug app.

| Area | Acceptance criterion | Pass | Fail | Evidence / notes |
| --- | --- | --- | --- | --- |
| Safe-mode isolation | Before launch, the executable contains the exact Debug-only static marker; it then passes the runtime probe, and every scenario confirms its unique ready token while using isolated defaults, storage, browser data, and disabled clipboard monitoring. | [ ] | [ ] | |
| Wide layout | `dark-zh-wide.png` and `light-en-wide.png` show the full history, detail pane, header, and actions without clipping or overlap. | [ ] | [ ] | |
| Compact layout | `light-en-compact.png` remains usable at 800 × 520 with no truncated primary controls or inaccessible content. | [ ] | [ ] | |
| Dark appearance | Dark materials, text, dividers, selection, and controls maintain legible contrast in `dark-zh-wide.png`. | [ ] | [ ] | |
| Light appearance | Light materials, text, dividers, selection, and controls maintain legible contrast in the English captures. | [ ] | [ ] | |
| Chinese localization | The Chinese wide capture uses Chinese UI copy and has no missing translations, placeholder keys, or clipped labels. | [ ] | [ ] | |
| English localization | The English captures use natural English copy and have no missing translations, placeholder keys, or clipped labels. | [ ] | [ ] | |
| Source and kind icons | Every seeded row shows its source-application icon and the correct text, rich-text, image, file, or link kind badge. | [ ] | [ ] | |
| Image thumbnail | The Preview PNG fixture renders a bounded image thumbnail without distortion, blank output, or layout shift. | [ ] | [ ] | |
| File thumbnail | The Finder fixture shows the system file icon/thumbnail for the caller-created local demo file. | [ ] | [ ] | |
| Selection state | The selected row has a clear outline/background treatment in both light and dark appearances. | [ ] | [ ] | |
| Hover state | Moving the pointer across rows and icon buttons produces a visible, stable hover treatment without flicker. | [ ] | [ ] | |
| Search | Typing a query filters the seeded fixtures, preserves focus, and exposes a clear empty state when nothing matches. | [ ] | [ ] | |
| Filter chips | Kind/favorite filter chips show selected state, combine correctly with search, and remain keyboard operable. | [ ] | [ ] | |
| Detail cards | Selecting each fixture updates preview, metadata, source, size, and content cards without stale values. | [ ] | [ ] | |
| Primary paste action | The primary paste action is visually dominant, labeled, keyboard reachable, and disabled only when appropriate. | [ ] | [ ] | |
| Settings layout | `light-en-settings.png` shows consistent section spacing, aligned labels/controls, and no clipping at the target size. | [ ] | [ ] | |
| Browser empty state | `light-en-browser-empty.png` uses the deterministic empty service (never live browser state) and shows the intended explanation and recovery/action affordance. | [ ] | [ ] | |
| Browser populated/error states | With browser tabs available or automation denied, populated and error states remain readable and actionable. | [ ] | [ ] | |
| Quick Look | `light-en-quick-look.png` comes from the PID-owned secondary high-layer preview window, never the main or Settings window, and visibly shows the seeded `public.png` fixture. | [ ] | [ ] | |
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
