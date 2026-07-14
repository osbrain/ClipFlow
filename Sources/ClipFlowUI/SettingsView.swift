import AppKit
import ClipFlowCore
import ClipFlowSystem
import SwiftUI

public struct SettingsView: View {
    @Bindable private var model: SettingsModel
    private let loginItemService: LoginItemService
    private let onRuntimeSettingsChange: @MainActor (
        AppSettingsRuntimeSnapshot,
        AppSettingsRuntimeSnapshot
    ) -> Void

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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                SettingsHeader()
                generalSection
                retentionSection
                permissionsSection
                startupSection
                detailFieldsSection
                diagnosticsSection
            }
            .padding(18)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .id(model.appLanguage)
        .environment(\.locale, L10n.locale)
        .onChange(of: snapshot) { previous, current in
            model.save()
            onRuntimeSettingsChange(previous.runtimeSnapshot, current.runtimeSnapshot)
        }
        .task { await model.refreshPermissions() }
    }

    private var generalSection: some View {
        GlassSection(title: L10n.string("settings.general"), icon: "gearshape") {
            VStack(spacing: 10) {
                menuRow(
                    icon: "command",
                    title: L10n.string("settings.shortcut"),
                    selection: $model.shortcut
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
                    selection: $model.appearanceMode
                ) {
                    ForEach(ClipFlowAppearanceMode.allCases, id: \.self) { appearance in
                        Text(L10n.string(appearance.localizationKey)).tag(appearance)
                    }
                }

                menuRow(
                    icon: "globe",
                    title: L10n.string("settings.language"),
                    selection: languageBinding
                ) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(L10n.string(language.localizationKey)).tag(language)
                    }
                }

                menuRow(
                    icon: "rectangle.compress.vertical",
                    title: L10n.string("settings.density"),
                    selection: $model.listDensity
                ) {
                    ForEach(ClipFlowListDensity.allCases, id: \.self) { density in
                        Text(L10n.string(density.localizationKey)).tag(density)
                    }
                }

                menuRow(
                    icon: "doc.on.clipboard",
                    title: L10n.string("settings.defaultPasteMode"),
                    selection: $model.defaultPasteMode
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

                    Button(action: Self.openAccessibilitySettings) {
                        Label(L10n.string("settings.openSystemSettings"), systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L10n.string("settings.openSystemSettings"))
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
                .onChange(of: model.launchAtLogin) {
                    try? loginItemService.setEnabled(model.launchAtLogin)
                }

                toggleRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: L10n.string("settings.autoUpdates"),
                    isOn: $model.autoCheckUpdatesEnabled
                )
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
            toggleRow(
                icon: "ladybug",
                title: L10n.string("settings.debugLogging"),
                isOn: $model.debugLoggingEnabled
            )
        }
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
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassRow(icon: icon, title: title) {
            Picker(title, selection: selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .accessibilityLabel(title)
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
            autoCheckUpdatesEnabled: model.autoCheckUpdatesEnabled,
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

private struct SettingsHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.68)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .shadow(color: Color.accentColor.opacity(0.24), radius: 10, y: 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("settings.title"))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(L10n.string("settings.subtitle"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
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
    let autoCheckUpdatesEnabled: Bool
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
