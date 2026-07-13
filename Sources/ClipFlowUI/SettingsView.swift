import AppKit
import ClipFlowSystem
import SwiftUI

public struct SettingsView: View {
    @Bindable private var model: SettingsModel
    private let loginItemService: LoginItemService

    public init(model: SettingsModel, loginItemService: LoginItemService) {
        self.model = model
        self.loginItemService = loginItemService
    }

    public var body: some View {
        TabView {
            Form {
                Picker("Global shortcut", selection: $model.shortcut) {
                    Text("Command-Shift-V").tag(HotKeyShortcut.commandShiftV)
                    Text("Option-Command-V").tag(HotKeyShortcut.optionCommandV)
                    Text("Option-Command-Space").tag(HotKeyShortcut.optionCommandSpace)
                    Text("Control-Option-Space").tag(HotKeyShortcut.controlOptionSpace)
                }
                Toggle("Show menu bar item", isOn: $model.showStatusBarItem)
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                    .onChange(of: model.launchAtLogin) {
                        try? loginItemService.setEnabled(model.launchAtLogin)
                    }
                Picker("Default paste mode", selection: $model.defaultPasteMode) {
                    Text("Original formatting").tag("original")
                    Text("Plain text").tag("plainText")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Picker("Keep history", selection: $model.retentionPolicy) {
                    Text("1 day").tag("day")
                    Text("1 week").tag("week")
                    Text("1 month").tag("month")
                    Text("Unlimited").tag("unlimited")
                }
                TextField("Maximum items", value: $model.maximumItemCount, format: .number)
                TextField("Storage limit (MB)", value: $model.maximumStorageMB, format: .number)
                Stepper(
                    "External payload threshold: \(model.externalPayloadThresholdMB) MB",
                    value: $model.externalPayloadThresholdMB,
                    in: 1...100
                )
            }
            .formStyle(.grouped)
            .tabItem { Label("Storage", systemImage: "externaldrive") }

            Form {
                LabeledContent("Accessibility") {
                    HStack {
                        Text(model.isAccessibilityTrusted ? "Granted" : "Not granted")
                            .foregroundStyle(model.isAccessibilityTrusted ? .green : .secondary)
                        Button("Open Settings") { Self.openAccessibilitySettings() }
                    }
                }
                Toggle("Browser tab management", isOn: $model.browserTabManagementEnabled)
                Toggle("Check for updates automatically", isOn: $model.autoCheckUpdatesEnabled)
            }
            .formStyle(.grouped)
            .tabItem { Label("Permissions", systemImage: "hand.raised") }

            Form {
                Toggle("Show source application", isOn: $model.showDetailSource)
                Toggle("Show content type", isOn: $model.showDetailType)
                Toggle("Show created time", isOn: $model.showDetailCreatedAt)
                Toggle("Show last-used time", isOn: $model.showDetailLastUsedAt)
                Toggle("Enable redacted debug logging", isOn: $model.debugLoggingEnabled)
            }
            .formStyle(.grouped)
            .tabItem { Label("Details", systemImage: "list.bullet.rectangle") }
        }
        .frame(width: 620, height: 430)
        .padding(12)
        .onChange(of: snapshot) { model.save() }
        .task { await model.refreshPermissions() }
    }

    private var snapshot: SettingsSnapshot {
        SettingsSnapshot(
            shortcut: model.shortcut,
            launchAtLogin: model.launchAtLogin,
            showStatusBarItem: model.showStatusBarItem,
            retentionPolicy: model.retentionPolicy,
            maximumItemCount: model.maximumItemCount,
            maximumStorageMB: model.maximumStorageMB,
            externalPayloadThresholdMB: model.externalPayloadThresholdMB,
            browserTabManagementEnabled: model.browserTabManagementEnabled,
            autoCheckUpdatesEnabled: model.autoCheckUpdatesEnabled,
            debugLoggingEnabled: model.debugLoggingEnabled,
            defaultPasteMode: model.defaultPasteMode,
            detailFlags: [
                model.showDetailSource, model.showDetailType,
                model.showDetailCreatedAt, model.showDetailLastUsedAt
            ]
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
    let launchAtLogin: Bool
    let showStatusBarItem: Bool
    let retentionPolicy: String
    let maximumItemCount: Int
    let maximumStorageMB: Int
    let externalPayloadThresholdMB: Int
    let browserTabManagementEnabled: Bool
    let autoCheckUpdatesEnabled: Bool
    let debugLoggingEnabled: Bool
    let defaultPasteMode: String
    let detailFlags: [Bool]
}

