import AppKit
import ClipFlowCore
import ClipFlowSystem
import SwiftUI

public enum SettingsControlLayout {
    public static let sidebarWidth: CGFloat = 172
    public static let menuWidth: CGFloat = 148
    static let menuHeight: CGFloat = 28
}

enum SettingsCategory: CaseIterable, Hashable, Identifiable {
    case general
    case storage
    case permissions
    case startup
    case details
    case diagnostics

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

    var sidebarTitleKey: String {
        switch self {
        case .general, .startup, .diagnostics:
            titleKey
        case .storage:
            "settings.sidebar.storage"
        case .permissions:
            "settings.sidebar.permissions"
        case .details:
            "settings.sidebar.details"
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

public struct SettingsView: View {
    @Bindable private var model: SettingsModel
    private let loginItemService: LoginItemService
    private let onRuntimeSettingsChange: @MainActor (
        AppSettingsRuntimeSnapshot,
        AppSettingsRuntimeSnapshot
    ) -> Void
    @State private var isRestoringLoginItem = false
    @State private var selectedCategory: SettingsCategory = .general

    public init(
        model: SettingsModel,
        loginItemService: LoginItemService,
        onRuntimeSettingsChange: @escaping @MainActor (
            AppSettingsRuntimeSnapshot,
            AppSettingsRuntimeSnapshot
        ) -> Void = { _, _ in }
    ) {
        self.model = model
        self.loginItemService = loginItemService
        self.onRuntimeSettingsChange = onRuntimeSettingsChange
    }

    public var body: some View {
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
        .id(model.appLanguage)
        .environment(\.locale, L10n.locale)
        .onChange(of: snapshot) { previous, current in
            model.save()
            let previousRuntime = previous.runtimeSnapshot
            let currentRuntime = current.runtimeSnapshot
            if previousRuntime != currentRuntime {
                onRuntimeSettingsChange(previousRuntime, currentRuntime)
            }
        }
        .task {
            await model.refreshPermissions()
            model.refreshDiagnostics()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await model.refreshPermissions()
            }
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsCategory.allCases) { category in
                Button {
                    selectedCategory = category
                } label: {
                    Label(
                        L10n.string(category.sidebarTitleKey),
                        systemImage: category.symbolName
                    )
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
                .accessibilityLabel(L10n.string(category.sidebarTitleKey))
                .help(L10n.string(category.sidebarTitleKey))
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
                    SettingsErrorBanner(
                        message: message,
                        dismiss: model.clearRuntimeError
                    )
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

    private var generalSection: some View {
        GlassSection(title: L10n.string("settings.general"), icon: "gearshape") {
            VStack(spacing: 10) {
                menuRow(
                    icon: "command",
                    title: L10n.string("settings.shortcut"),
                    selection: $model.shortcut,
                    valueLabel: L10n.string(model.shortcut.localizationKey)
                ) {
                    ForEach(HotKeyShortcut.allCases, id: \.self) { shortcut in
                        Text(L10n.string(shortcut.localizationKey)).tag(shortcut)
                    }
                }

                toggleRow(
                    icon: "menubar.rectangle",
                    title: L10n.string("settings.showMenuBar"),
                    isOn: $model.showStatusBarItem
                )

                menuRow(
                    icon: "circle.lefthalf.filled",
                    title: L10n.string("settings.appearance"),
                    selection: $model.appearanceMode,
                    valueLabel: L10n.string(model.appearanceMode.localizationKey)
                ) {
                    ForEach(ClipFlowAppearanceMode.allCases, id: \.self) { appearance in
                        Text(L10n.string(appearance.localizationKey)).tag(appearance)
                    }
                }

                menuRow(
                    icon: "globe",
                    title: L10n.string("settings.language"),
                    selection: languageBinding,
                    valueLabel: L10n.string(model.appLanguage.localizationKey)
                ) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(L10n.string(language.localizationKey)).tag(language)
                    }
                }

                menuRow(
                    icon: "rectangle.compress.vertical",
                    title: L10n.string("settings.density"),
                    selection: $model.listDensity,
                    valueLabel: L10n.string(model.listDensity.localizationKey)
                ) {
                    ForEach(ClipFlowListDensity.allCases, id: \.self) { density in
                        Text(L10n.string(density.localizationKey)).tag(density)
                    }
                }

                menuRow(
                    icon: "doc.on.clipboard",
                    title: L10n.string("settings.defaultPasteMode"),
                    selection: $model.defaultPasteMode,
                    valueLabel: L10n.string("settings.paste.\(model.defaultPasteMode)")
                ) {
                    Text(L10n.string("settings.paste.original")).tag("original")
                    Text(L10n.string("settings.paste.plainText")).tag("plainText")
                }
            }
        }
    }

    private var retentionSection: some View {
        GlassSection(title: L10n.string("settings.retention"), icon: "externaldrive") {
            VStack(spacing: 10) {
                GlassRow(icon: "clock.arrow.circlepath", title: L10n.string("settings.retention")) {
                    Picker(L10n.string("settings.retention"), selection: $model.retention) {
                        ForEach(RetentionPreference.allCases, id: \.self) { preference in
                            Text(L10n.string(preference.localizationKey)).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel(L10n.string("settings.retention"))
                    .help(L10n.string("settings.retention"))
                }

                integerFieldRow(
                    icon: "list.number",
                    title: L10n.string("settings.maximumItems"),
                    value: $model.maximumItemCount
                )

                integerFieldRow(
                    icon: "internaldrive",
                    title: L10n.string("settings.storageLimit"),
                    value: $model.maximumStorageMB,
                    unit: L10n.string("settings.unit.megabytes")
                )

                GlassRow(icon: "doc.badge.arrow.up", title: L10n.string("settings.externalThreshold")) {
                    Text(model.externalPayloadThresholdMB, format: .number)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(L10n.string("settings.unit.megabytes"))
                        .foregroundStyle(.secondary)
                    Stepper(
                        value: $model.externalPayloadThresholdMB,
                        in: 1...100
                    ) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .accessibilityLabel(L10n.string("settings.externalThreshold"))
                    .help(L10n.string("settings.externalThreshold"))
                }
            }
        }
    }

    private var permissionsSection: some View {
        GlassSection(title: L10n.string("settings.permissions"), icon: "hand.raised") {
            VStack(spacing: 10) {
                GlassRow(icon: "accessibility", title: L10n.string("settings.accessibility")) {
                    Text(
                        L10n.string(
                            model.isAccessibilityTrusted
                                ? "settings.permission.granted"
                                : "settings.permission.notGranted"
                        )
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(model.isAccessibilityTrusted ? .green : .secondary)

                    Button {
                        Task { await model.refreshPermissions() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L10n.string("settings.refreshPermission"))
                    .help(L10n.string("settings.refreshPermission"))

                    Button {
                        Task {
                            await model.requestAccessibilityAuthorization()
                            if !model.isAccessibilityTrusted {
                                Self.openAccessibilitySettings()
                            }
                        }
                    } label: {
                        Label(L10n.string("settings.openSystemSettings"), systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L10n.string("settings.openSystemSettings"))

                    if !model.isAccessibilityTrusted {
                        Button {
                            Task {
                                await model.resetAccessibilityAuthorization()
                                await model.requestAccessibilityAuthorization()
                                Self.openAccessibilitySettings()
                            }
                        } label: {
                            Label(
                                L10n.string("settings.resetAccessibility"),
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(L10n.string("settings.resetAccessibilityHelp"))
                    }
                }

                toggleRow(
                    icon: "globe",
                    title: L10n.string("settings.browserTabs"),
                    isOn: $model.browserTabManagementEnabled
                )
                toggleRow(
                    icon: "paperplane",
                    title: L10n.string("settings.feishuAction"),
                    isOn: $model.feishuActionEnabled
                )
                toggleRow(
                    icon: "sparkles",
                    title: L10n.string("settings.doubaoAction"),
                    isOn: $model.doubaoActionEnabled
                )
            }
        }
    }

    private var startupSection: some View {
        GlassSection(title: L10n.string("settings.startup"), icon: "power") {
            VStack(spacing: 10) {
                toggleRow(
                    icon: "macwindow.badge.plus",
                    title: L10n.string("settings.launchAtLogin"),
                    isOn: $model.launchAtLogin
                )
                .onChange(of: model.launchAtLogin) { previous, current in
                    if isRestoringLoginItem {
                        isRestoringLoginItem = false
                        return
                    }
                    do {
                        try loginItemService.setEnabled(current)
                        model.clearRuntimeError()
                    } catch {
                        model.reportRuntimeError(
                            L10n.format("settings.error.loginItem", error.localizedDescription)
                        )
                        isRestoringLoginItem = true
                        model.launchAtLogin = previous
                    }
                }
            }
        }
    }

    private var detailFieldsSection: some View {
        GlassSection(title: L10n.string("settings.details"), icon: "list.bullet.rectangle") {
            VStack(spacing: 10) {
                toggleRow(
                    icon: "app.badge",
                    title: L10n.string("settings.showSource"),
                    isOn: $model.showDetailSource
                )
                toggleRow(
                    icon: "doc.text.magnifyingglass",
                    title: L10n.string("settings.showKind"),
                    isOn: $model.showDetailType
                )
                toggleRow(
                    icon: "calendar.badge.clock",
                    title: L10n.string("settings.showCreated"),
                    isOn: $model.showDetailCreatedAt
                )
                toggleRow(
                    icon: "clock.arrow.2.circlepath",
                    title: L10n.string("settings.showLastUsed"),
                    isOn: $model.showDetailLastUsedAt
                )
                toggleRow(
                    icon: "scalemass",
                    title: L10n.string("settings.showSize"),
                    isOn: $model.showDetailSize
                )
                toggleRow(
                    icon: "textformat",
                    title: L10n.string("settings.showFormatting"),
                    isOn: $model.showDetailFormatting
                )
            }
        }
    }

    private var diagnosticsSection: some View {
        GlassSection(title: L10n.string("settings.diagnostics"), icon: "stethoscope") {
            VStack(spacing: 10) {
                toggleRow(
                    icon: "ladybug",
                    title: L10n.string("settings.debugLogging"),
                    isOn: $model.debugLoggingEnabled
                )

                GlassRow(icon: "doc.text", title: L10n.string("settings.logPath")) {
                    Text(
                        model.diagnosticLogURL?.path
                            ?? L10n.string("settings.logNotCreated")
                    )
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.diagnosticLogURL?.path ?? L10n.string("settings.logNotCreated"))

                    Button {
                        revealDiagnosticLog()
                    } label: {
                        Label(L10n.string("settings.revealLog"), systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!model.isDiagnosticLogAvailable)
                    .help(L10n.string("settings.revealLog"))
                }
            }
        }
    }

    private func revealDiagnosticLog() {
        guard let url = model.diagnosticLogURL,
              model.isDiagnosticLogAvailable else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        GlassRow(icon: icon, title: title) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
                .help(title)
        }
    }

    private func menuRow<Value: Hashable, Content: View>(
        icon: String,
        title: String,
        selection: Binding<Value>,
        valueLabel: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassRow(icon: icon, title: title) {
            Picker(title, selection: selection, content: content)
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(
                    width: SettingsControlLayout.menuWidth,
                    height: SettingsControlLayout.menuHeight
                )
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel(title)
                .accessibilityValue(valueLabel)
                .help(title)
        }
    }

    private func integerFieldRow(
        icon: String,
        title: String,
        value: Binding<Int>,
        unit: String? = nil
    ) -> some View {
        GlassRow(icon: icon, title: title) {
            TextField(title, value: value, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 104)
                .accessibilityLabel(title)
                .help(title)
            if let unit {
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var snapshot: SettingsSnapshot {
        SettingsSnapshot(
            shortcut: model.shortcut,
            appearanceMode: model.appearanceMode,
            listDensity: model.listDensity,
            appLanguage: model.appLanguage,
            launchAtLogin: model.launchAtLogin,
            showStatusBarItem: model.showStatusBarItem,
            retention: model.retention,
            maximumItemCount: model.maximumItemCount,
            maximumStorageMB: model.maximumStorageMB,
            externalPayloadThresholdMB: model.externalPayloadThresholdMB,
            browserTabManagementEnabled: model.browserTabManagementEnabled,
            feishuActionEnabled: model.feishuActionEnabled,
            doubaoActionEnabled: model.doubaoActionEnabled,
            debugLoggingEnabled: model.debugLoggingEnabled,
            defaultPasteMode: model.defaultPasteMode,
            detailFlags: [
                model.showDetailSource, model.showDetailType,
                model.showDetailCreatedAt, model.showDetailLastUsedAt,
                model.showDetailSize, model.showDetailFormatting
            ]
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { model.appLanguage },
            set: { language in
                L10n.configure(language: language)
                model.appLanguage = language
            }
        )
    }

    private static func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct SettingsSnapshot: Equatable {
    let shortcut: HotKeyShortcut
    let appearanceMode: ClipFlowAppearanceMode
    let listDensity: ClipFlowListDensity
    let appLanguage: AppLanguage
    let launchAtLogin: Bool
    let showStatusBarItem: Bool
    let retention: RetentionPreference
    let maximumItemCount: Int
    let maximumStorageMB: Int
    let externalPayloadThresholdMB: Int
    let browserTabManagementEnabled: Bool
    let feishuActionEnabled: Bool
    let doubaoActionEnabled: Bool
    let debugLoggingEnabled: Bool
    let defaultPasteMode: String
    let detailFlags: [Bool]

    var runtimeSnapshot: AppSettingsRuntimeSnapshot {
        AppSettingsRuntimeSnapshot(
            shortcut: shortcut,
            showStatusBarItem: showStatusBarItem,
            appLanguage: appLanguage,
            defaultPasteMode: PasteMode(rawValue: defaultPasteMode) ?? .original,
            externalPayloadThresholdMB: externalPayloadThresholdMB,
            retention: RetentionSettings(
                preference: retention,
                maximumItemCount: maximumItemCount,
                maximumStorageMB: maximumStorageMB
            ),
            debugLoggingEnabled: debugLoggingEnabled
        )
    }
}

private struct SettingsErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help(L10n.string("settings.dismissError"))
            .accessibilityLabel(L10n.string("settings.dismissError"))
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.orange.opacity(0.28), lineWidth: 1)
        )
    }
}

private extension HotKeyShortcut {
    var localizationKey: String {
        switch self {
        case .commandShiftV: "settings.shortcut.commandShiftV"
        case .optionCommandV: "settings.shortcut.optionCommandV"
        case .optionCommandSpace: "settings.shortcut.optionCommandSpace"
        case .controlOptionSpace: "settings.shortcut.controlOptionSpace"
        case .optionCommandC: "settings.shortcut.optionCommandC"
        }
    }
}

private extension ClipFlowAppearanceMode {
    var localizationKey: String { "settings.appearance.\(rawValue)" }
}

private extension ClipFlowListDensity {
    var localizationKey: String { "settings.density.\(rawValue)" }
}

private extension RetentionPreference {
    var localizationKey: String { "retention.\(rawValue)" }
}
