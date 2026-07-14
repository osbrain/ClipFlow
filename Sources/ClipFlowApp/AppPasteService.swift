import ClipFlowCore
import ClipFlowStorage
import ClipFlowSystem
import ClipFlowUI
import Foundation

actor AppPasteService: PasteServing {
    private let repository: ClipboardRepository
    private let coordinator: PasteCoordinator
    private let modeResolver: PasteModeResolver
    private var target: PasteTarget?

    init(
        repository: ClipboardRepository,
        coordinator: PasteCoordinator,
        modeResolver: PasteModeResolver
    ) {
        self.repository = repository
        self.coordinator = coordinator
        self.modeResolver = modeResolver
    }

    func setTarget(_ target: PasteTarget?) {
        self.target = target
    }

    func updateDefaultMode(_ mode: PasteMode) {
        modeResolver.updateDefaultMode(mode)
    }

    func resolvedMode(for bundleID: String?) -> PasteMode {
        modeResolver.mode(for: bundleID)
    }

    func paste(item: ClipboardItem) async throws -> PasteOutcome {
        guard let target else { throw AppPasteServiceError.noTargetApplication }
        return try await paste(
            item: item,
            mode: modeResolver.mode(for: target.bundleID)
        )
    }

    func paste(item: ClipboardItem, mode: PasteMode) async throws -> PasteOutcome {
        guard let target else { throw AppPasteServiceError.noTargetApplication }
        let payloads = try repository.payloads(for: item.id).map {
            NormalizedPayload(itemIndex: $0.itemIndex, type: $0.type, data: $0.data)
        }
        return try await coordinator.paste(
            PasteRequest(
                payloads: payloads,
                mode: mode
            ),
            target: target
        )
    }
}

enum AppPasteServiceError: LocalizedError {
    case noTargetApplication

    var errorDescription: String? {
        "The previous application is no longer available."
    }
}
