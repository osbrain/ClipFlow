# Detail Actions and Scrollbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Normalize detail action button sizing and render genuinely thin, low-contrast overlay scroll indicators.

**Architecture:** Centralize product metrics in `ClipFlowVisualStyle`, apply a small SwiftUI button style to all detail actions, and replace native scroller drawing with a compact `NSScroller` subclass configured by the existing scroll probe.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Testing

---

### Task 1: Visual metrics

**Files:**
- Modify: `Tests/ClipFlowCoreTests/WindowExperienceTests.swift`
- Modify: `Sources/ClipFlowUI/ClipFlowVisualStyle.swift`

- [ ] Add failing assertions for primary height 42, secondary height 36, utility height 30, indicator thickness 4, and opacity at most 0.30.
- [ ] Run `swift run ClipFlowCoreTests` and confirm missing metric failures.
- [ ] Add the exact constants to `ClipFlowVisualStyle`.
- [ ] Run the test suite and confirm the metric tests pass.

### Task 2: Detail action style

**Files:**
- Modify: `Sources/ClipFlowUI/DetailView.swift`

- [ ] Add `DetailActionButtonKind` and `DetailActionButtonStyle` using 42/36/30pt heights and 12/10/8pt radii.
- [ ] Replace native large and compact bordered button styling while preserving actions, keyboard shortcuts, accessibility labels, and help text.
- [ ] Run `swift run ClipFlowCoreTests` and confirm no behavior regressions.

### Task 3: Thin overlay scroller

**Files:**
- Modify: `Tests/ClipFlowCoreTests/WindowExperienceTests.swift`
- Modify: `Sources/ClipFlowUI/WindowExperience.swift`

- [ ] Add failing tests for vertical and horizontal 4pt indicator rectangles.
- [ ] Run `swift run ClipFlowCoreTests` and confirm the geometry API is missing.
- [ ] Implement shared indicator geometry and `ClipFlowOverlayScroller`, then install it on vertical and horizontal scroll views.
- [ ] Run all tests and visual acceptance captures.

### Task 4: Package and launch

**Files:**
- Modify only if verification exposes a defect.

- [ ] Run `./scripts/package-app.sh release` and `./scripts/verify-local-app.sh`.
- [ ] Restart `artifacts/ClipFlow.app` and visually inspect the live interface.
- [ ] Commit on `main` with the configured project-local author.

