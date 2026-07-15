import Foundation
import Testing
import ClipFlowCore
import ClipFlowSystem
@testable import ClipFlowUI

@Suite("Settings model")
@MainActor
struct SettingsModelTests {
    @Test("settings menu controls use a compact fixed width")
    func settingsMenuControlsUseCompactFixedWidth() {
        #expect(SettingsControlLayout.menuWidth == 168)
    }

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
        model.save()

        let restored = SettingsModel(store: store, permissions: permissions)
        #expect(!restored.showDetailSize)
        #expect(!restored.showDetailFormatting)
    }

    @Test("legacy automatic update preference is ignored")
    func ignoresLegacyAutomaticUpdatePreference() {
        let store = MemorySettingsStore(values: ["autoCheckUpdatesEnabled": true])
        let model = SettingsModel(
            store: store,
            permissions: FakePermissionStatus(accessibilityTrusted: false)
        )

        model.save()

        #expect(!Mirror(reflecting: model).children.contains {
            $0.label == "autoCheckUpdatesEnabled"
        })
        #expect(!store.writtenKeys.contains("autoCheckUpdatesEnabled"))
    }

    @Test("runtime errors can be reported and cleared")
    func reportsAndClearsRuntimeErrors() {
        let model = SettingsModel(
            store: MemorySettingsStore(),
            permissions: FakePermissionStatus(accessibilityTrusted: false)
        )

        model.reportRuntimeError("Shortcut is unavailable")
        #expect(model.runtimeErrorMessage == "Shortcut is unavailable")

        model.clearRuntimeError()
        #expect(model.runtimeErrorMessage == nil)
    }

    @Test("diagnostic log availability follows the configured file")
    func refreshesDiagnosticLogAvailability() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let logURL = root.appendingPathComponent("ClipFlow.log")
        let model = SettingsModel(
            store: MemorySettingsStore(),
            permissions: FakePermissionStatus(accessibilityTrusted: false),
            diagnosticLogURL: logURL
        )

        model.refreshDiagnostics()
        #expect(model.diagnosticLogURL == logURL)
        #expect(!model.isDiagnosticLogAvailable)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("log".utf8).write(to: logURL)
        model.refreshDiagnostics()
        #expect(model.isDiagnosticLogAvailable)
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

    @Test("requesting Accessibility prompts once and refreshes permission state")
    func requestsAccessibilityAuthorization() async {
        let permissions = FakePermissionStatus(
            accessibilityTrusted: false,
            grantsOnRequest: true
        )
        let model = SettingsModel(
            store: MemorySettingsStore(),
            permissions: permissions
        )

        await model.requestAccessibilityAuthorization()

        #expect(permissions.requestCount == 1)
        #expect(model.isAccessibilityTrusted)
    }

    @Test("resetting Accessibility removes a stale grant before requesting the current app")
    func resetsStaleAccessibilityAuthorization() async {
        let permissions = FakePermissionStatus(accessibilityTrusted: true)
        let model = SettingsModel(
            store: MemorySettingsStore(),
            permissions: permissions
        )

        await model.resetAccessibilityAuthorization()

        #expect(permissions.resetCount == 1)
        #expect(!model.isAccessibilityTrusted)
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

    @Test("runtime settings detect every live service change independently")
    func runtimeSettingsDetectIndependentChanges() {
        let baseline = AppSettingsRuntimeSnapshot(
            shortcut: .commandShiftV,
            showStatusBarItem: true,
            appLanguage: .system,
            defaultPasteMode: .original,
            externalPayloadThresholdMB: 4,
            retention: RetentionSettings(
                preference: .month,
                maximumItemCount: 10_000,
                maximumStorageMB: 2_048
            ),
            debugLoggingEnabled: false
        )
        let cases: [(AppSettingsRuntimeSnapshot, AppSettingsRuntimeChange)] = [
            (.init(copying: baseline, shortcut: .optionCommandV), .shortcut),
            (.init(copying: baseline, showStatusBarItem: false), .statusItem),
            (.init(copying: baseline, appLanguage: .simplifiedChinese), .language),
            (.init(copying: baseline, defaultPasteMode: .plainText), .pasteMode),
            (.init(copying: baseline, externalPayloadThresholdMB: 8), .externalPayloadThreshold),
            (
                .init(
                    copying: baseline,
                    retention: RetentionSettings(
                        preference: .week,
                        maximumItemCount: 10_000,
                        maximumStorageMB: 2_048
                    )
                ),
                .retention
            ),
            (.init(copying: baseline, debugLoggingEnabled: true), .debugLogging)
        ]

        for (snapshot, expected) in cases {
            #expect(snapshot.changes(from: baseline) == [expected])
        }
    }
}

private final class MemorySettingsStore: SettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any]

    init(values: [String: Any] = [:]) {
        self.values = values
    }

    private var written = Set<String>()

    var writtenKeys: Set<String> {
        lock.withLock { written }
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
        lock.withLock {
            values[key] = value
            written.insert(key)
        }
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
    private let grantsOnRequest: Bool
    private var requests = 0
    private var resets = 0

    init(accessibilityTrusted: Bool, grantsOnRequest: Bool = false) {
        trusted = accessibilityTrusted
        self.grantsOnRequest = grantsOnRequest
    }

    var accessibilityTrusted: Bool {
        get { lock.withLock { trusted } }
        set { lock.withLock { trusted = newValue } }
    }

    func isAccessibilityTrusted() -> Bool {
        accessibilityTrusted
    }

    var requestCount: Int {
        lock.withLock { requests }
    }

    var resetCount: Int {
        lock.withLock { resets }
    }

    func requestAccessibilityAuthorization() -> Bool {
        lock.withLock {
            requests += 1
            if grantsOnRequest {
                trusted = true
            }
            return trusted
        }
    }

    func resetAccessibilityAuthorization() {
        lock.withLock {
            resets += 1
            trusted = false
        }
    }
}
