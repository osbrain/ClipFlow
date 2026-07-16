import ClipFlowCore
import ClipFlowStorage
import Foundation

public protocol ClipboardCaptureRepository: Sendable {
    func upsert(
        _ capture: NormalizedCapture,
        itemID: UUID?,
        timestamp: Date
    ) throws -> ClipboardUpsertResult

    func applyRetention(_ policy: RetentionPolicy, now: Date) throws -> [UUID]
}

extension ClipboardRepository: ClipboardCaptureRepository {}

public enum ClipboardCaptureProcessingOutcome: Equatable, Sendable {
    case inserted
    case refreshedIncrementally
    case refreshedWithReload
    case ignored
    case failed
}

public actor ClipboardCaptureProcessor {
    public typealias RetentionPolicyProvider = @Sendable () -> RetentionPolicy
    public typealias LogHandler = @Sendable (
        _ event: String,
        _ metadata: [String: String]
    ) async -> Void

    private let normalizer: ClipboardNormalizer
    private let repository: any ClipboardCaptureRepository
    private let model: AppModel
    private let retentionPolicy: RetentionPolicyProvider
    private let log: LogHandler
    private let now: @Sendable () -> Date

    public init(
        normalizer: ClipboardNormalizer,
        repository: any ClipboardCaptureRepository,
        model: AppModel,
        retentionPolicy: @escaping RetentionPolicyProvider,
        log: @escaping LogHandler = { _, _ in },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.normalizer = normalizer
        self.repository = repository
        self.model = model
        self.retentionPolicy = retentionPolicy
        self.log = log
        self.now = now
    }

    @discardableResult
    public func process(
        _ capture: RawClipboardCapture
    ) async -> ClipboardCaptureProcessingOutcome {
        do {
            let normalized = try normalizer.normalize(capture)
            let timestamp = now()
            let result = try repository.upsert(
                normalized,
                itemID: nil,
                timestamp: timestamp
            )
            await log(
                "capture",
                [
                    "kind": normalized.kind.rawValue,
                    "byteCount": "\(normalized.byteSize)",
                    "disposition": result.disposition == .inserted
                        ? "inserted"
                        : "refreshed"
                ]
            )

            switch result.disposition {
            case .inserted:
                let deleted = try repository.applyRetention(
                    retentionPolicy(),
                    now: timestamp
                )
                if !deleted.isEmpty {
                    await log(
                        "retention_cleanup",
                        ["deletedCount": "\(deleted.count)"]
                    )
                }
                await model.reload()
                return .inserted

            case .refreshed:
                let refreshedInPlace = await model.refreshCapturedItem(result.item)
                if refreshedInPlace {
                    return .refreshedIncrementally
                }
                await model.reload()
                return .refreshedWithReload
            }
        } catch ClipboardNormalizationError.noUsablePayload {
            return .ignored
        } catch {
            await log("capture_error", ["message": error.localizedDescription])
            return .failed
        }
    }
}
