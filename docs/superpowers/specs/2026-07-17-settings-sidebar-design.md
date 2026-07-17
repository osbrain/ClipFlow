# Settings sidebar design

## Goal

Replace ClipFlow's single scrolling settings page with a compact two-column
settings window inspired by the supplied reference: persistent navigation on
the left and the selected category's form on the right. The window remains a
fixed 700 by 700 points.

## Layout

- The root view uses an `HStack` with a 172-point sidebar and a flexible
  detail pane. Both panes retain the app's material background and rounded,
  low-contrast visual language.
- The sidebar stays visible while the right pane scrolls. It lists six
  categories, each with an SF Symbol: General, Storage, Permissions, Startup,
  Details, and Diagnostics.
- A selected sidebar row receives the app accent color, white icon/text, and a
  rounded highlight. Unselected rows use the normal primary/secondary color
  hierarchy and remain accessible as buttons.
- The detail pane has a compact category title and optional runtime-error
  banner above a scroll view. Existing `GlassSection` and `GlassRow` content
  stays intact so the right pane continues to look and behave like ClipFlow.

## Categories and settings

| Category | Existing settings shown |
| --- | --- |
| General | Shortcut, menu-bar item, appearance, language, density, default paste mode |
| Storage | Retention, maximum items, storage limit, external payload threshold |
| Permissions | Accessibility state/actions, browser tab management, Feishu action, Doubao action |
| Startup | Launch at login |
| Details | Source, type, created time, last-used time, size, formatting display flags |
| Diagnostics | Debug logging, diagnostic log path, reveal-log action |

## Behavior and state

- The selection is view-local state and defaults to General whenever the
  settings view is created. It is not persisted, because it does not alter the
  user's ClipFlow configuration.
- Existing settings bindings, persistence, runtime-change notifications,
  login-item failure recovery, diagnostics refresh, and permission polling are
  unchanged.
- A runtime error is rendered above the selected category form so failed
  actions remain visible without changing category selection.
- The existing compact menu control width is reduced only as needed for the
  700-point window. It remains a single-line accessible menu label.

## Validation

- Update window-layout tests to assert the 700 by 700 fixed size remains.
- Add deterministic tests for the category metadata/order and compact control
  dimensions when those values are exposed from the UI module.
- Run the focused Swift test suite and launch the visual-acceptance settings
  view to inspect sidebar selection, form scrolling, light/dark appearance,
  and Chinese/English labels.

## Scope

This change reorganizes presentation only. It introduces no settings,
persistence keys, feature behavior, or window-resizing changes.
