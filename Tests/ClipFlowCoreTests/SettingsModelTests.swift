import Foundation
import Testing
@testable import ClipFlowUI

@Suite("Settings model")
@MainActor
struct SettingsModelTests {
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
}

private final class MemorySettingsStore: SettingsStoring, @unchecked Sendable {
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
