import ClipFlowCore
import ClipFlowStorage
import ClipFlowSystem
import ClipFlowUI
import Foundation

final class AppRetentionPolicyStore: @unchecked Sendable {
    private let lock = NSLock()
    private var policy: RetentionPolicy

    init(policy: RetentionPolicy) {
        self.policy = policy
    }

    func update(_ policy: RetentionPolicy) {
        lock.withLock { self.policy = policy }
    }

    func current() -> RetentionPolicy {
        lock.withLock { policy }
    }
}

@MainActor
final class AppSettingsCoordinator {
    private let repository: ClipboardRepository
    private let pasteService: AppPasteService
    private let logger: LocalLogger
    private let retentionPolicyStore: AppRetentionPolicyStore
    private let updateShortcut: (HotKeyShortcut, HotKeyShortcut) throws -> Void
    private let updateStatusItem: (Bool) -> Void
    private let updateLanguage: (AppLanguage) -> Void

    init(
        repository: ClipboardRepository,
        pasteService: AppPasteService,
        logger: LocalLogger,
        retentionPolicyStore: AppRetentionPolicyStore,
        updateShortcut: @escaping (HotKeyShortcut, HotKeyShortcut) throws -> Void,
        updateStatusItem: @escaping (Bool) -> Void,
        updateLanguage: @escaping (AppLanguage) -> Void
    ) {
        self.repository = repository
        self.pasteService = pasteService
        self.logger = logger
        self.retentionPolicyStore = retentionPolicyStore
        self.updateShortcut = updateShortcut
        self.updateStatusItem = updateStatusItem
        self.updateLanguage = updateLanguage
    }

    func apply(
        previous: AppSettingsRuntimeSnapshot,
        current: AppSettingsRuntimeSnapshot
    ) async throws {
        let changes = current.changes(from: previous)

        if changes.contains(.shortcut) {
            do {
                try updateShortcut(current.shortcut, previous.shortcut)
            } catch {
                throw AppSettingsCoordinatorError.shortcutRegistrationFailed(error)
            }
        }
        if changes.contains(.language) {
            updateLanguage(current.appLanguage)
        }
        if changes.contains(.statusItem) || changes.contains(.language) {
            updateStatusItem(current.showStatusBarItem)
        }
        if changes.contains(.pasteMode) {
            await pasteService.updateDefaultMode(current.defaultPasteMode)
        }
        if changes.contains(.externalPayloadThreshold) {
            repository.updateExternalPayloadThreshold(
                bytes: current.externalPayloadThresholdMB * 1_048_576
            )
        }
        if changes.contains(.retention) {
            let policy = current.retention.policy
            retentionPolicyStore.update(policy)
            let deleted: [UUID]
            do {
                deleted = try repository.applyRetention(policy)
            } catch {
                throw AppSettingsCoordinatorError.retentionFailed(error)
            }
            await logger.log("retention_cleanup", metadata: ["deletedCount": "\(deleted.count)"])
        }
        if changes.contains(.debugLogging) {
            await logger.setEnabled(current.debugLoggingEnabled)
            await logger.log(
                "debug_logging_changed",
                metadata: ["enabled": "\(current.debugLoggingEnabled)"]
            )
        }
    }
}

enum AppSettingsCoordinatorError: Error {
    case shortcutRegistrationFailed(any Error)
    case retentionFailed(any Error)
}
