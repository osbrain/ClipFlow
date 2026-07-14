# Local App Accessibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a stable locally signed `ClipFlow.app` and request macOS Accessibility authorization from Settings.

**Architecture:** Extend the existing permission provider so the settings model owns request-and-refresh behavior. Add a deterministic shell packager that assembles the SwiftPM executable and resource bundle into an Ad-hoc signed application with a fixed Bundle ID.

**Tech Stack:** Swift 6.2, SwiftUI, ApplicationServices, Swift Testing, Bash, codesign

---

### Task 1: Accessibility request behavior

**Files:**
- Modify: `Tests/ClipFlowCoreTests/SettingsModelTests.swift`
- Modify: `Sources/ClipFlowUI/SettingsModel.swift`
- Modify: `Sources/ClipFlowUI/SettingsView.swift`

- [ ] Add a failing model test that calls `requestAccessibilityAuthorization()` and verifies the provider received one request and the model refreshed to trusted.
- [ ] Run `swift run ClipFlowCoreTests` and confirm the missing API failure.
- [ ] Add `requestAccessibilityAuthorization()` to the provider and model; system implementation calls `AXIsProcessTrustedWithOptions` with the prompt option.
- [ ] Wire the Settings button to request authorization and open the pane only while still untrusted.
- [ ] Run `swift run ClipFlowCoreTests` and confirm all tests pass.

### Task 2: Standard local application package

**Files:**
- Create: `Config/Info.plist`
- Create: `scripts/package-app.sh`

- [ ] Define `CFBundleIdentifier = com.aiesst.clipflow`, `CFBundleExecutable = ClipFlowApp`, `CFBundlePackageType = APPL`, version fields, `LSUIElement`, and minimum macOS version.
- [ ] Build the requested configuration with `swift build`, copy `ClipFlowApp` and `ClipFlow_ClipFlowUI.bundle`, and sign the completed package with `codesign --sign - --force --deep`.
- [ ] Validate plist syntax, fixed identity, executable presence, resource presence, and signature.

### Task 3: Verify and launch

**Files:**
- Modify only if verification exposes a defect in Tasks 1-2.

- [ ] Run the complete test suite.
- [ ] Run `./scripts/package-app.sh debug` and verify the application identity and signature.
- [ ] Stop the bare `.build/debug/ClipFlowApp` process.
- [ ] Launch `artifacts/ClipFlow.app` and confirm the running executable path is inside the application bundle.
- [ ] Commit the implementation with the project-local `aiesst <aiesst.labs@gmail.com>` identity.

