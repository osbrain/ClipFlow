# Settings Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the fixed 700 by 700 ClipFlow settings window into a persistent sidebar and a scrollable selected-category form.

**Architecture:** Add a small presentation-only category enum to `SettingsView.swift`; it is the single source of truth for sidebar labels, SF Symbols, and the selected form. Keep all existing model bindings and section builders, but render exactly one of them in a right-side scroll view. The left sidebar owns only local selection state and never changes persisted preferences.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Testing, existing visual-acceptance shell script.

---

## File structure

- Modify: `Sources/ClipFlowUI/SettingsView.swift` — category metadata, 700-point sidebar/detail layout, compact title, and selected-section routing.
- Modify: `Tests/ClipFlowCoreTests/SettingsModelTests.swift` — deterministic metadata and layout constants tests.
- Modify: `Tests/ClipFlowCoreTests/WindowExperienceTests.swift` — retain the fixed 700 by 700 settings window guarantee.
- Modify: `docs/superpowers/plans/2026-07-17-settings-sidebar.md` — mark each executed step complete as work progresses.

### Task 1: Define presentation metadata and lock it down with tests

**Files:**
- Modify: `Tests/ClipFlowCoreTests/SettingsModelTests.swift:7-15`
- Modify: `Sources/ClipFlowUI/SettingsView.swift:6-10`

- [ ] **Step 1: Write failing tests for compact layout and category metadata**

  Add these cases below `settingsMenuControlsUseCompactFixedWidth()`:

  ```swift
  @Test("settings sidebar uses stable compact dimensions")
  func settingsSidebarUsesStableCompactDimensions() {
      #expect(SettingsControlLayout.sidebarWidth == 172)
      #expect(SettingsControlLayout.menuWidth == 148)
  }

  @Test("settings categories have a stable sidebar order")
  func settingsCategoriesHaveStableSidebarOrder() {
      #expect(SettingsCategory.allCases == [
          .general, .storage, .permissions, .startup, .details, .diagnostics
      ])
      #expect(SettingsCategory.general.symbolName == "gearshape")
      #expect(SettingsCategory.storage.symbolName == "externaldrive")
      #expect(SettingsCategory.permissions.symbolName == "hand.raised")
      #expect(SettingsCategory.startup.symbolName == "power")
      #expect(SettingsCategory.details.symbolName == "list.bullet.rectangle")
      #expect(SettingsCategory.diagnostics.symbolName == "stethoscope")
  }
  ```

- [ ] **Step 2: Run the focused tests and verify the expected compile failure**

  Run:

  ```bash
  swift run ClipFlowCoreTests
  ```

  Expected: the build fails because `sidebarWidth` and `SettingsCategory` are not declared, and the prior `menuWidth == 168` expectation no longer matches the requested compact layout.

- [ ] **Step 3: Add the minimal presentation types**

  Replace the layout declaration at the top of `Sources/ClipFlowUI/SettingsView.swift` and add the enum immediately after it:

  ```swift
  public enum SettingsControlLayout {
      public static let sidebarWidth: CGFloat = 172
      public static let menuWidth: CGFloat = 148
      static let menuHeight: CGFloat = 28
  }

  enum SettingsCategory: CaseIterable, Hashable, Identifiable {
      case general, storage, permissions, startup, details, diagnostics

      var id: Self { self }

      var titleKey: String {
          switch self {
          case .general: "settings.general"
          case .storage: "settings.retention"
          case .permissions: "settings.permissions"
          case .startup: "settings.startup"
          case .details: "settings.details"
          case .diagnostics: "settings.diagnostics"
          }
      }

      var symbolName: String {
          switch self {
          case .general: "gearshape"
          case .storage: "externaldrive"
          case .permissions: "hand.raised"
          case .startup: "power"
          case .details: "list.bullet.rectangle"
          case .diagnostics: "stethoscope"
          }
      }
  }
  ```

- [ ] **Step 4: Run the focused tests and verify they pass**

  Run:

  ```bash
  swift run ClipFlowCoreTests
  ```

  Expected: `Settings model` tests pass, including both sidebar metadata checks.

- [ ] **Step 5: Commit the presentation metadata**

  ```bash
  git add Sources/ClipFlowUI/SettingsView.swift Tests/ClipFlowCoreTests/SettingsModelTests.swift
  git commit -m "test: define settings sidebar metadata"
  ```

### Task 2: Render the persistent sidebar and selected detail pane

**Files:**
- Modify: `Sources/ClipFlowUI/SettingsView.swift:12-77`
- Modify: `Sources/ClipFlowUI/SettingsView.swift:485-514`

- [ ] **Step 1: Add view-local selection state**

  Directly after `isRestoringLoginItem`, add:

  ```swift
  @State private var selectedCategory: SettingsCategory = .general
  ```

- [ ] **Step 2: Replace the root scroll view with a two-column root**

  Replace the current `body` content before `.id(model.appLanguage)` with the following structure, retaining its existing background, language, change observer, and task modifiers:

  ```swift
  HStack(spacing: 0) {
      settingsSidebar
      Divider()
      settingsDetail
  }
  .background {
      Rectangle()
          .fill(.regularMaterial)
          .ignoresSafeArea()
  }
  ```

  Add these computed views before `generalSection`:

  ```swift
  private var settingsSidebar: some View {
      VStack(alignment: .leading, spacing: 6) {
          ForEach(SettingsCategory.allCases) { category in
              Button {
                  selectedCategory = category
              } label: {
                  Label(L10n.string(category.titleKey), systemImage: category.symbolName)
                      .font(.body.weight(.medium))
                      .frame(maxWidth: .infinity, alignment: .leading)
                      .padding(.horizontal, 12)
                      .padding(.vertical, 9)
                      .foregroundStyle(
                          selectedCategory == category ? Color.white : Color.primary
                      )
                      .background(
                          selectedCategory == category ? Color.accentColor : Color.clear,
                          in: RoundedRectangle(cornerRadius: 9)
                      )
              }
              .buttonStyle(.plain)
              .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
              .accessibilityLabel(L10n.string(category.titleKey))
              .help(L10n.string(category.titleKey))
          }
          Spacer(minLength: 0)
      }
      .padding(12)
      .frame(width: SettingsControlLayout.sidebarWidth, alignment: .topLeading)
  }

  private var settingsDetail: some View {
      ScrollView {
          LazyVStack(alignment: .leading, spacing: 16) {
              Text(L10n.string(selectedCategory.titleKey))
                  .font(.title2.weight(.semibold))
              if let message = model.runtimeErrorMessage {
                  SettingsErrorBanner(message: message, dismiss: model.clearRuntimeError)
              }
              selectedSection
          }
          .padding(18)
      }
      .clipFlowScrollAppearance()
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private var selectedSection: some View {
      switch selectedCategory {
      case .general: generalSection
      case .storage: retentionSection
      case .permissions: permissionsSection
      case .startup: startupSection
      case .details: detailFieldsSection
      case .diagnostics: diagnosticsSection
      }
  }
  ```

- [ ] **Step 3: Remove the superseded single-page header**

  Delete the `SettingsHeader` private view because the selected-category title replaces it. Do not remove `SettingsErrorBanner`, `SettingsSnapshot`, or any section builder.

- [ ] **Step 4: Build the app**

  Run:

  ```bash
  swift build
  ```

  Expected: build completes successfully with no changes to model or persistence APIs.

- [ ] **Step 5: Commit the layout implementation**

  ```bash
  git add Sources/ClipFlowUI/SettingsView.swift
  git commit -m "feat: organize settings with a sidebar"
  ```

### Task 3: Verify fixed window behavior and regressions

**Files:**
- Modify: `Tests/ClipFlowCoreTests/WindowExperienceTests.swift:115-130`
- Modify: `Tests/ClipFlowCoreTests/SettingsModelTests.swift:7-30`

- [ ] **Step 1: Add a fixed-size regression assertion**

  In `settingsWindowControlsAndSize()`, retain the existing exact 700 by 700 expectation and append:

  ```swift
  #expect(window.frame.size == SettingsWindowAppearance.contentSize)
  ```

  This protects the user-approved fixed window size after the sidebar is introduced.

- [ ] **Step 2: Run focused UI and window tests**

  Run:

  ```bash
  swift run ClipFlowCoreTests
  ```

  Expected: both suites pass; no test changes model persistence or AppKit window appearance assumptions.

- [ ] **Step 3: Run the complete test suite**

  Run:

  ```bash
  swift test
  ```

  Expected: all tests pass.

- [ ] **Step 4: Capture the existing English and Chinese settings scenarios**

  Run:

  ```bash
  scripts/capture-visual-acceptance.sh
  ```

  Inspect `artifacts/visual-acceptance/light-en-settings.png` and `artifacts/visual-acceptance/dark-zh-settings.png`. Confirm the sidebar is continuously visible, General is selected by default, the detail pane does not overlap the macOS traffic lights, and the Chinese labels remain single line at 700 by 700.

- [ ] **Step 5: Commit the regression test**

  ```bash
  git add Tests/ClipFlowCoreTests/WindowExperienceTests.swift
  git commit -m "test: preserve settings window size"
  ```
