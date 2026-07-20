import ClipFlowCore
import ClipFlowStorage
import ClipFlowSystem
import Foundation

public protocol ClipboardCaptureRepository: Sendable {
    func upsert(
        _ capture: NormalizedCapture,
        itemID: UUID?,
        timestamp: Date
    ) throws -> ClipboardUpsertResult

    func applyRetention(_ policy: RetentionPolicy, now: Date) throws -> [UUID]
    func allCategories() throws -> [ClipCategory]
    func createCategory(name: String) throws -> ClipCategory
    func assign(itemID: UUID, categoryID: UUID) throws
    func updateRecognizedText(_ text: String, for itemID: UUID) throws
}

extension ClipboardRepository: ClipboardCaptureRepository {}

public enum ClipboardCaptureProcessingOutcome: Equatable, Sendable {
    case inserted
    case refreshedIncrementally
    case refreshedWithReload
    case ignored
    case ignoredByPrivacy
    case failed
}

public actor ClipboardCaptureProcessor {
    public typealias RetentionPolicyProvider = @Sendable () -> RetentionPolicy
    public typealias LogHandler = @Sendable (
        _ event: String,
        _ metadata: [String: String]
    ) async -> Void
    public typealias PrivacyPolicyProvider = @Sendable () async -> PrivacyCapturePolicy
    public typealias SmartCategoryPolicyProvider = @Sendable () async -> SmartCategoryPolicy

    private let normalizer: ClipboardNormalizer
    private let repository: any ClipboardCaptureRepository
    private let model: AppModel
    private let retentionPolicy: RetentionPolicyProvider
    private let log: LogHandler
    private let privacyPolicy: PrivacyPolicyProvider
    private let smartCategoryPolicy: SmartCategoryPolicyProvider
    private let textRecognizer: (any LocalTextRecognizing)?
    private let now: @Sendable () -> Date

    public init(
        normalizer: ClipboardNormalizer,
        repository: any ClipboardCaptureRepository,
        model: AppModel,
        retentionPolicy: @escaping RetentionPolicyProvider,
        privacyPolicy: @escaping PrivacyPolicyProvider = {
            PrivacyCapturePolicy(
                excludedAppIdentifiers: [],
                excludedContentPatterns: [],
                ignoresSensitiveText: true
            )
        },
        smartCategoryPolicy: @escaping SmartCategoryPolicyProvider = {
            SmartCategoryPolicy(isEnabled: false)
        },
        textRecognizer: (any LocalTextRecognizing)? = nil,
        log: @escaping LogHandler = { _, _ in },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.normalizer = normalizer
        self.repository = repository
        self.model = model
        self.retentionPolicy = retentionPolicy
        self.log = log
        self.privacyPolicy = privacyPolicy
        self.smartCategoryPolicy = smartCategoryPolicy
        self.textRecognizer = textRecognizer
        self.now = now
    }

    @discardableResult
    public func process(
        _ capture: RawClipboardCapture
    ) async -> ClipboardCaptureProcessingOutcome {
        do {
            let normalized = try normalizer.normalize(capture)
            guard await privacyPolicy().allows(normalized) else {
                await log(
                    "capture_ignored",
                    ["reason": "privacy", "kind": normalized.kind.rawValue]
                )
                return .ignoredByPrivacy
            }
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
                await applySmartCategoryIfNeeded(to: result.item, capture: normalized)
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
                await recognizeTextIfPossible(for: normalized, itemID: result.item.id)
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

    private func applySmartCategoryIfNeeded(
        to item: ClipboardItem,
        capture: NormalizedCapture
    ) async {
        guard let suggestion = await smartCategoryPolicy().suggestion(for: capture) else {
            return
        }

        do {
            let category = try category(for: suggestion)
            try repository.assign(itemID: item.id, categoryID: category.id)
            await log(
                "automatic_category",
                ["category": suggestion.rawValue, "kind": capture.kind.rawValue]
            )
        } catch {
            await log(
                "automatic_category_error",
                ["category": suggestion.rawValue, "message": error.localizedDescription]
            )
        }
    }

    private func recognizeTextIfPossible(
        for capture: NormalizedCapture,
        itemID: UUID
    ) async {
        guard capture.kind == .image, let textRecognizer else { return }
        do {
            guard let text = try await textRecognizer.recognizeText(in: capture),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            try repository.updateRecognizedText(text, for: itemID)
            await model.reload()
            await log("capture_ocr", ["itemID": itemID.uuidString])
        } catch {
            await log("capture_ocr_error", ["message": error.localizedDescription])
        }
    }

    private func category(for suggestion: SmartCategory) throws -> ClipCategory {
        if let existing = try repository.allCategories().first(where: {
            suggestion.matches(categoryName: $0.name)
        }) {
            return existing
        }
        return try repository.createCategory(name: suggestion.localizedName)
    }
}
