import ClipFlowCore
import ClipFlowSystem
import Foundation

public struct RetentionSettings: Equatable, Sendable {
    public let preference: RetentionPreference
    public let maximumItemCount: Int
    public let maximumStorageMB: Int

    public init(
        preference: RetentionPreference,
        maximumItemCount: Int,
        maximumStorageMB: Int
    ) {
        self.preference = preference
        self.maximumItemCount = max(100, maximumItemCount)
        self.maximumStorageMB = max(100, maximumStorageMB)
    }

    public var policy: RetentionPolicy {
        RetentionPolicy(
            maxAge: preference.maxAge,
            maxItemCount: maximumItemCount,
            maxBytes: maximumStorageMB * 1_048_576
        )
    }
}

public struct AppSettingsRuntimeSnapshot: Equatable, Sendable {
    public let shortcut: HotKeyShortcut
    public let showStatusBarItem: Bool
    public let appLanguage: AppLanguage
    public let defaultPasteMode: PasteMode
    public let externalPayloadThresholdMB: Int
    public let retention: RetentionSettings
    public let debugLoggingEnabled: Bool
    public let mainPanelOpacityPercent: Int

    public init(
        shortcut: HotKeyShortcut,
        showStatusBarItem: Bool,
        appLanguage: AppLanguage,
        defaultPasteMode: PasteMode,
        externalPayloadThresholdMB: Int,
        retention: RetentionSettings,
        debugLoggingEnabled: Bool,
        mainPanelOpacityPercent: Int = MainPanelOpacity.defaultPercent
    ) {
        self.shortcut = shortcut
        self.showStatusBarItem = showStatusBarItem
        self.appLanguage = appLanguage
        self.defaultPasteMode = defaultPasteMode
        self.externalPayloadThresholdMB = max(1, externalPayloadThresholdMB)
        self.retention = retention
        self.debugLoggingEnabled = debugLoggingEnabled
        self.mainPanelOpacityPercent = MainPanelOpacity.clampedPercent(mainPanelOpacityPercent)
    }

    public init(
        copying snapshot: Self,
        shortcut: HotKeyShortcut? = nil,
        showStatusBarItem: Bool? = nil,
        appLanguage: AppLanguage? = nil,
        defaultPasteMode: PasteMode? = nil,
        externalPayloadThresholdMB: Int? = nil,
        retention: RetentionSettings? = nil,
        debugLoggingEnabled: Bool? = nil,
        mainPanelOpacityPercent: Int? = nil
    ) {
        self.init(
            shortcut: shortcut ?? snapshot.shortcut,
            showStatusBarItem: showStatusBarItem ?? snapshot.showStatusBarItem,
            appLanguage: appLanguage ?? snapshot.appLanguage,
            defaultPasteMode: defaultPasteMode ?? snapshot.defaultPasteMode,
            externalPayloadThresholdMB:
                externalPayloadThresholdMB ?? snapshot.externalPayloadThresholdMB,
            retention: retention ?? snapshot.retention,
            debugLoggingEnabled: debugLoggingEnabled ?? snapshot.debugLoggingEnabled,
            mainPanelOpacityPercent:
                mainPanelOpacityPercent ?? snapshot.mainPanelOpacityPercent
        )
    }

    public func changes(from previous: Self) -> Set<AppSettingsRuntimeChange> {
        var changes = Set<AppSettingsRuntimeChange>()
        if shortcut != previous.shortcut { changes.insert(.shortcut) }
        if showStatusBarItem != previous.showStatusBarItem { changes.insert(.statusItem) }
        if appLanguage != previous.appLanguage { changes.insert(.language) }
        if defaultPasteMode != previous.defaultPasteMode { changes.insert(.pasteMode) }
        if externalPayloadThresholdMB != previous.externalPayloadThresholdMB {
            changes.insert(.externalPayloadThreshold)
        }
        if retention != previous.retention { changes.insert(.retention) }
        if debugLoggingEnabled != previous.debugLoggingEnabled { changes.insert(.debugLogging) }
        if mainPanelOpacityPercent != previous.mainPanelOpacityPercent {
            changes.insert(.panelOpacity)
        }
        return changes
    }
}

public enum AppSettingsRuntimeChange: Hashable, Sendable {
    case shortcut
    case statusItem
    case language
    case pasteMode
    case externalPayloadThreshold
    case retention
    case debugLogging
    case panelOpacity
}

public extension RetentionPreference {
    var maxAge: TimeInterval? {
        switch self {
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        case .month: 30 * 24 * 60 * 60
        case .unlimited: nil
        }
    }
}
