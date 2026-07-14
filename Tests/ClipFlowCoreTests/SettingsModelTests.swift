import Foundation
import Testing
@testable import ClipFlowUI

@Suite("Settings model")
@MainActor
struct SettingsModelTests {
    @Test("retention preferences have stable stored values")
    func retentionPreferencesHaveStableStoredValues() {
        #expect(RetentionPreference.day.rawValue == "day")
        #expect(RetentionPreference.week.rawValue == "week")
        #expect(RetentionPreference.month.rawValue == "month")
        #expect(RetentionPreference.unlimited.rawValue == "unlimited")
        #expect(RetentionPreference.allCases == [.day, .week, .month, .unlimited])
    }

    @Test("loads retention from the legacy storage key and defaults unknown values safely")
    func loadsRetentionFromLegacyKeyAndDefaultsUnknownValues() {
        let permissions = FakePermissionStatus(accessibilityTrusted: false)
        let migratedStore = MemorySettingsStore(values: ["retentionPolicy": "week"])
        let migrated = SettingsModel(store: migratedStore, permissions: permissions)
        #expect(migrated.retention == .week)

        let unknownStore = MemorySettingsStore(values: ["retentionPolicy": "future-policy"])
        let unknown = SettingsModel(store: unknownStore, permissions: permissions)
        #expect(unknown.retention == .month)

        let empty = SettingsModel(store: MemorySettingsStore(), permissions: permissions)
        #expect(empty.retention == .month)
    }

    @Test("retention round-trips through the existing storage key")
    func retentionRoundTripsThroughExistingStorageKey() {
        let store = MemorySettingsStore()
        let permissions = FakePermissionStatus(accessibilityTrusted: false)
        let model = SettingsModel(store: store, permissions: permissions)

        model.retention = .unlimited
        model.save()

        #expect(store.string(forKey: "retentionPolicy") == "unlimited")
        #expect(SettingsModel(store: store, permissions: permissions).retention == .unlimited)
    }

    @Test("new detail fields default to visible and persist")
    func newDetailFieldsDefaultToVisibleAndPersist() {
        let store = MemorySettingsStore()
        let permissions = FakePermissionStatus(accessibilityTrusted: false)
        let model = SettingsModel(store: store, permissions: permissions)

        #expect(model.showDetailSize)
        #expect(model.showDetailFormatting)

        model.showDetailSize = false
        model.showDetailFormatting = false
        model.save()

        let restored = SettingsModel(store: store, permissions: permissions)
        #expect(!restored.showDetailSize)
        #expect(!restored.showDetailFormatting)
        #expect(store.bool(forKey: "showDetailSize") == false)
        #expect(store.bool(forKey: "showDetailFormatting") == false)
    }

    @Test("settings store presence preserves persisted false values")
    func settingsStorePresencePreservesPersistedFalseValues() {
        let store = AccuratePresenceSettingsStore()
        let permissions = FakePermissionStatus(accessibilityTrusted: false)
        let model = SettingsModel(store: store, permissions: permissions)

        model.showDetailSize = false
        model.showDetailFormatting = false
        model.autoCheckUpdatesEnabled = false
        model.save()

        let restored = SettingsModel(store: store, permissions: permissions)
        #expect(!restored.showDetailSize)
        #expect(!restored.showDetailFormatting)
        #expect(!restored.autoCheckUpdatesEnabled)
    }

    @Test("clamps storage threshold and refreshes permission state")
    func clampsThresholdAndRefreshesPermissions() async {
        let store = MemorySettingsStore()
        let permissions = FakePermissionStatus(accessibilityTrusted: false)
        let model = SettingsModel(store: store, permissions: permissions)

        model.externalPayloadThresholdMB = 0
        model.save()
        #expect(store.integer(forKey: "externalPayloadThresholdMB") == 1)

        permissions.accessibilityTrusted = true
        await model.refreshPermissions()
        #expect(model.isAccessibilityTrusted)
    }

    @Test("persists appearance and density preferences")
    func persistsAppearanceAndDensityPreferences() {
        let store = MemorySettingsStore()
        let permissions = FakePermissionStatus(accessibilityTrusted: false)
        let model = SettingsModel(store: store, permissions: permissions)

        model.appearanceMode = .dark
        model.listDensity = .compact
        model.save()

        let restored = SettingsModel(store: store, permissions: permissions)
        #expect(restored.appearanceMode == .dark)
        #expect(restored.listDensity == .compact)
    }

    @Test("persists an explicit application language")
    func persistsApplicationLanguage() {
        let store = MemorySettingsStore()
        let permissions = FakePermissionStatus(accessibilityTrusted: false)
        let model = SettingsModel(store: store, permissions: permissions)

        #expect(model.appLanguage == .system)
        model.appLanguage = .simplifiedChinese
        model.save()

        #expect(store.string(forKey: "appLanguage") == "zh-Hans")
        #expect(
            SettingsModel(store: store, permissions: permissions).appLanguage ==
                .simplifiedChinese
        )
    }
}

private final class MemorySettingsStore: SettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any]

    init(values: [String: Any] = [:]) {
        self.values = values
    }

    func bool(forKey key: String) -> Bool {
        lock.withLock { values[key] as? Bool ?? false }
    }

    func integer(forKey key: String) -> Int {
        lock.withLock { values[key] as? Int ?? 0 }
    }

    func string(forKey key: String) -> String? {
        lock.withLock { values[key] as? String }
    }

    func set(_ value: Any?, forKey key: String) {
        lock.withLock { values[key] = value }
    }

    func containsValue(forKey key: String) -> Bool {
        lock.withLock { values[key] != nil }
    }
}

private final class AccuratePresenceSettingsStore: SettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    func bool(forKey key: String) -> Bool {
        lock.withLock { values[key] as? Bool ?? false }
    }

    func integer(forKey key: String) -> Int {
        lock.withLock { values[key] as? Int ?? 0 }
    }

    func string(forKey key: String) -> String? {
        lock.withLock { values[key] as? String }
    }

    func set(_ value: Any?, forKey key: String) {
        lock.withLock { values[key] = value }
    }

    func containsValue(forKey key: String) -> Bool {
        lock.withLock { values[key] != nil }
    }
}

private final class FakePermissionStatus: PermissionStatusProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var trusted: Bool

    init(accessibilityTrusted: Bool) {
        trusted = accessibilityTrusted
    }

    var accessibilityTrusted: Bool {
        get { lock.withLock { trusted } }
        set { lock.withLock { trusted = newValue } }
    }

    func isAccessibilityTrusted() -> Bool {
        accessibilityTrusted
    }
}
