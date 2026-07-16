# ClipFlow First-Run Onboarding Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved dense two-column first-run onboarding with live Accessibility status and complete visual acceptance coverage.

**Architecture:** Add small presentation and layout types in `ClipFlowUI`, then rebuild `OnboardingView` from focused subviews that consume those types. Extend the existing isolated visual-acceptance environment with an onboarding flag rather than adding a separate preview application.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit/ApplicationServices, Swift Testing, Bash visual-acceptance capture.

---

### Task 1: Onboarding presentation contract

**Files:**
- Create: `Sources/ClipFlowUI/OnboardingPresentation.swift`
- Test: `Tests/ClipFlowCoreTests/OnboardingPresentationTests.swift`

- [ ] Write failing tests that require an 800×520 minimum layout, a 250-point hero column, and different pending/granted button and status localization keys.
- [ ] Run `swift run ClipFlowCoreTests` and confirm compilation fails because `OnboardingLayout` and `OnboardingPermissionPresentation` do not exist.
- [ ] Implement `OnboardingLayout` constants and `OnboardingPermissionPresentation.init(isTrusted:)` with stable localization keys and completion state.
- [ ] Run `swift run ClipFlowCoreTests` and confirm the new suite passes.

### Task 2: Dense two-column onboarding view

**Files:**
- Modify: `Sources/ClipFlowUI/OnboardingView.swift`
- Modify: `Sources/ClipFlowUI/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ClipFlowUI/Resources/zh-Hans.lproj/Localizable.strings`
- Test: `Tests/ClipFlowCoreTests/ClipboardKindPresentationTests.swift`

- [ ] Add all approved product, privacy, permission, shortcut, skip, and completion localization keys to the localization parity test and verify it fails.
- [ ] Replace the centered onboarding stack with a full-size two-column `HStack`, a compact brand/capability hero, and a flexible setup column containing three bounded rows.
- [ ] Make the permission action request authorization and open Accessibility Settings only while still untrusted; keep the onboarding presentation state active during the external-settings transition.
- [ ] Refresh permission state on entry and every second while onboarding is visible.
- [ ] Add both “Not now” and primary completion controls, with the primary label determined by the permission presentation state.
- [ ] Add matching English and Simplified Chinese translations and run `swift run ClipFlowCoreTests`.

### Task 3: Deterministic onboarding visual acceptance

**Files:**
- Modify: `Sources/ClipFlowApp/ClipFlowApp.swift`
- Modify: `scripts/capture-visual-acceptance.sh`
- Modify: `Tests/ClipFlowCoreTests/VisualAcceptanceConfigurationTests.swift`

- [ ] Add a failing test requiring `VisualAcceptanceConfiguration` to recognize `CLIPFLOW_SHOW_ONBOARDING=1`.
- [ ] Add `showsOnboarding` to the validated visual configuration and set `hasCompletedOnboarding` to the inverse value in the isolated defaults suite.
- [ ] Add a Chinese light-mode 800×520 onboarding scenario to the capture script.
- [ ] Run `./scripts/capture-visual-acceptance.sh` and inspect `artifacts/visual-acceptance/light-zh-onboarding.png` for clipping, overlap, excessive whitespace, correct button hierarchy, and correct localized copy.

### Task 4: Release verification

**Files:**
- Modify only files required by verification findings.

- [ ] Run `swift run ClipFlowCoreTests` and require zero failures.
- [ ] Run `swift build --product ClipFlowApp` and `swift build -c release --product ClipFlowApp`.
- [ ] Run `git diff --check`.
- [ ] Package the Release app and DMG using the existing scripts, verify the Ad-hoc signature, and record the SHA-256 checksum.
- [ ] Commit the implementation as `feat: redesign first-run onboarding` with author `aiesst <aiesst.labs@gmail.com>`.
