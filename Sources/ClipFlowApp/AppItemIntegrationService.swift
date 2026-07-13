import AppKit
import ClipFlowCore
import ClipFlowStorage
import ClipFlowSystem
import ClipFlowUI
import Foundation

@MainActor
final class AppItemIntegrationService: ItemIntegrationServing {
    private let repository: ClipboardRepository
    private let settings: SettingsModel
    private let previewController: QuickLookPreviewController
    private let dragWriter: ClipboardDragWriter
    private let actionRunner: ApplicationActionRunner

    init(
        repository: ClipboardRepository,
        settings: SettingsModel,
        clipboard: SystemClipboard
    ) {
        self.repository = repository
        self.settings = settings
        previewController = QuickLookPreviewController()
        dragWriter = ClipboardDragWriter()
        actionRunner = ApplicationActionRunner(
            clipboard: clipboard,
            launcher: SystemApplicationActionLauncher(),
            pastePoster: SystemApplicationActionPastePoster()
        )
    }

    func availableActions(for item: ClipboardItem) -> [ApplicationAction] {
        let installed = Set(ApplicationAction.allCases.flatMap(\.bundleIdentifiers).filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        })
        var enabled: Set<ApplicationAction> = []
        if settings.feishuActionEnabled { enabled.insert(.openFeishu) }
        if settings.doubaoActionEnabled { enabled.insert(.askDoubao) }
        return ApplicationActions(
            installedBundleIDs: installed,
            enabledActions: enabled
        ).available(for: item.kind)
    }

    func preview(_ item: ClipboardItem) throws {
        try previewController.show(
            payloads: payloads(for: item),
            suggestedName: item.displayTitle
        )
    }

    func dragProvider(for item: ClipboardItem) -> NSItemProvider? {
        try? dragWriter.itemProvider(
            for: payloads(for: item),
            suggestedName: item.displayTitle
        )
    }

    func perform(_ action: ApplicationAction, for item: ClipboardItem) async throws {
        try await actionRunner.perform(action, payloads: payloads(for: item))
    }

    private func payloads(for item: ClipboardItem) throws -> [NormalizedPayload] {
        try repository.payloads(for: item.id).map {
            NormalizedPayload(itemIndex: $0.itemIndex, type: $0.type, data: $0.data)
        }
    }
}
