@preconcurrency import ApplicationServices
import ClipFlowCore
import ClipFlowSystem
import Foundation
import Observation

public protocol SettingsStoring: Sendable {
    func bool(forKey key: String) -> Bool
    func integer(forKey key: String) -> Int
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
    func containsValue(forKey key: String) -> Bool
}

extension UserDefaults: SettingsStoring {
    public func containsValue(forKey key: String) -> Bool {
        object(forKey: key) != nil
    }
}

public protocol PermissionStatusProviding: Sendable {
    func isAccessibilityTrusted() -> Bool
    func requestAccessibilityAuthorization() -> Bool
}

public struct SystemPermissionStatus: PermissionStatusProviding {
    public init() {}
    public func isAccessibilityTrusted() -> Bool { AXIsProcessTrusted() }

    public func requestAccessibilityAuthorization() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions(
            [promptKey: true] as CFDictionary
        )
    }
}

public enum RetentionPreference: String, CaseIterable, Sendable {
    case day
    case week
    case month
    case unlimited
}

@MainActor
@Observable
public final class SettingsModel {
    public var shortcut: HotKeyShortcut
    public var appearanceMode: ClipFlowAppearanceMode
    public var listDensity: ClipFlowListDensity
    public var appLanguage: AppLanguage
    public var launchAtLogin: Bool
    public var showStatusBarItem: Bool
    public var retention: RetentionPreference
    public var maximumItemCount: Int
    public var maximumStorageMB: Int
    public var externalPayloadThresholdMB: Int
    public var browserTabManagementEnabled: Bool
    public var feishuActionEnabled: Bool
    public var doubaoActionEnabled: Bool
    public var debugLoggingEnabled: Bool
    public var defaultPasteMode: String
    public var showDetailSource: Bool
    public var showDetailType: Bool
    public var showDetailCreatedAt: Bool
    public var showDetailLastUsedAt: Bool
    public var showDetailSize: Bool
    public var showDetailFormatting: Bool
    public private(set) var isAccessibilityTrusted = false
    public private(set) var runtimeErrorMessage: String?
    public let diagnosticLogURL: URL?
    public private(set) var isDiagnosticLogAvailable = false

    @ObservationIgnored private let store: any SettingsStoring
    @ObservationIgnored private let permissions: any PermissionStatusProviding

    public init(
        store: any SettingsStoring = UserDefaults.standard,
        permissions: any PermissionStatusProviding = SystemPermissionStatus(),
        diagnosticLogURL: URL? = nil
    ) {
        self.store = store
        self.permissions = permissions
        self.diagnosticLogURL = diagnosticLogURL

        shortcut = HotKeyShortcut(
            rawValue: store.string(forKey: "showPanelHotKey") ?? ""
        ) ?? .commandShiftV
        appearanceMode = ClipFlowAppearanceMode(
            rawValue: store.string(forKey: "appearanceMode") ?? ""
        ) ?? .system
        listDensity = ClipFlowListDensity(
            rawValue: store.string(forKey: "listDensity") ?? ""
        ) ?? .comfortable
        appLanguage = AppLanguage(
            rawValue: store.string(forKey: "appLanguage") ?? ""
        ) ?? .system
        launchAtLogin = store.bool(forKey: "launchAtLogin")
        showStatusBarItem = store.containsValue(forKey: "showStatusBarItem")
            ? store.bool(forKey: "showStatusBarItem") : true
        retention = RetentionPreference(
            rawValue: store.string(forKey: "retentionPolicy") ?? ""
        ) ?? .month
        maximumItemCount = max(100, store.integer(forKey: "maximumItemCount"))
        if store.integer(forKey: "maximumItemCount") == 0 { maximumItemCount = 10_000 }
        maximumStorageMB = max(100, store.integer(forKey: "maximumStorageMB"))
        if store.integer(forKey: "maximumStorageMB") == 0 { maximumStorageMB = 2_048 }
        externalPayloadThresholdMB = max(1, store.integer(forKey: "externalPayloadThresholdMB"))
        browserTabManagementEnabled = store.bool(forKey: "browserTabManagementEnabled")
        feishuActionEnabled = store.bool(forKey: "feishuActionEnabled")
        doubaoActionEnabled = store.bool(forKey: "doubaoActionEnabled")
        debugLoggingEnabled = store.bool(forKey: "debugLoggingEnabled")
        defaultPasteMode = store.string(forKey: "defaultPasteMode") ?? "original"
        showDetailSource = store.containsValue(forKey: "showDetailSource")
            ? store.bool(forKey: "showDetailSource") : true
        showDetailType = store.containsValue(forKey: "showDetailType")
            ? store.bool(forKey: "showDetailType") : true
        showDetailCreatedAt = store.containsValue(forKey: "showDetailCreatedAt")
            ? store.bool(forKey: "showDetailCreatedAt") : true
        showDetailLastUsedAt = store.containsValue(forKey: "showDetailLastUsedAt")
            ? store.bool(forKey: "showDetailLastUsedAt") : true
        showDetailSize = store.containsValue(forKey: "showDetailSize")
            ? store.bool(forKey: "showDetailSize") : true
        showDetailFormatting = store.containsValue(forKey: "showDetailFormatting")
            ? store.bool(forKey: "showDetailFormatting") : true
        isAccessibilityTrusted = permissions.isAccessibilityTrusted()
    }

    public func save() {
        externalPayloadThresholdMB = max(1, externalPayloadThresholdMB)
        maximumItemCount = max(100, maximumItemCount)
        maximumStorageMB = max(100, maximumStorageMB)

        store.set(shortcut.rawValue, forKey: "showPanelHotKey")
        store.set(appearanceMode.rawValue, forKey: "appearanceMode")
        store.set(listDensity.rawValue, forKey: "listDensity")
        store.set(appLanguage.rawValue, forKey: "appLanguage")
        store.set(launchAtLogin, forKey: "launchAtLogin")
        store.set(showStatusBarItem, forKey: "showStatusBarItem")
        store.set(retention.rawValue, forKey: "retentionPolicy")
        store.set(maximumItemCount, forKey: "maximumItemCount")
        store.set(maximumStorageMB, forKey: "maximumStorageMB")
        store.set(externalPayloadThresholdMB, forKey: "externalPayloadThresholdMB")
        store.set(browserTabManagementEnabled, forKey: "browserTabManagementEnabled")
        store.set(feishuActionEnabled, forKey: "feishuActionEnabled")
        store.set(doubaoActionEnabled, forKey: "doubaoActionEnabled")
        store.set(debugLoggingEnabled, forKey: "debugLoggingEnabled")
        store.set(defaultPasteMode, forKey: "defaultPasteMode")
        store.set(showDetailSource, forKey: "showDetailSource")
        store.set(showDetailType, forKey: "showDetailType")
        store.set(showDetailCreatedAt, forKey: "showDetailCreatedAt")
        store.set(showDetailLastUsedAt, forKey: "showDetailLastUsedAt")
        store.set(showDetailSize, forKey: "showDetailSize")
        store.set(showDetailFormatting, forKey: "showDetailFormatting")
    }

    public func refreshPermissions() async {
        isAccessibilityTrusted = permissions.isAccessibilityTrusted()
    }

    public func requestAccessibilityAuthorization() async {
        _ = permissions.requestAccessibilityAuthorization()
        isAccessibilityTrusted = permissions.isAccessibilityTrusted()
    }

    public func reportRuntimeError(_ message: String) {
        runtimeErrorMessage = message
    }

    public func clearRuntimeError() {
        runtimeErrorMessage = nil
    }

    public func refreshDiagnostics() {
        guard let diagnosticLogURL else {
            isDiagnosticLogAvailable = false
            return
        }
        isDiagnosticLogAvailable = FileManager.default.fileExists(
            atPath: diagnosticLogURL.path
        )
    }

    public var runtimeSnapshot: AppSettingsRuntimeSnapshot {
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
