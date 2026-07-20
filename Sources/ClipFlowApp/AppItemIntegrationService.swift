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
    private let clipboard: SystemClipboard
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
        self.clipboard = clipboard
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

    func availableContextActions(for item: ClipboardItem) -> [ItemContextAction] {
        let payloads = try? payloads(for: item)
        let fileURL = payloads.flatMap(Self.fileURL)
        let linkURL = payloads.flatMap(Self.linkURL)

        return ItemContextAction.available(for: item.kind).filter { action in
            switch action {
            case .openLink:
                linkURL != nil
            case .openFile, .revealInFinder:
                fileURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
            case .copyMarkdownLink:
                linkURL != nil
            case .copyFilePath:
                fileURL != nil
            case .copyPlainText, .copyCleanText, .copyFirstLine:
                payloads.flatMap(SystemClipboard.plainText(from:))
                    .map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } == true
            case .copyURLs:
                payloads.flatMap(SystemClipboard.plainText(from:))
                    .map { !ContentActionTransformer.extractedURLs(from: $0).isEmpty } == true
            case .pasteOriginal, .pastePlainText, .pasteFilePath,
                 .copyOriginal, .quickLook:
                true
            }
        }
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

    func perform(_ action: ItemContextAction, for item: ClipboardItem) throws {
        let payloads = try payloads(for: item)
        switch action {
        case .openLink:
            guard let url = Self.linkURL(from: payloads),
                  NSWorkspace.shared.open(url) else {
                throw ItemContextActionError.unavailable
            }
        case .openFile:
            guard let url = Self.fileURL(from: payloads),
                  FileManager.default.fileExists(atPath: url.path),
                  NSWorkspace.shared.open(url) else {
                throw ItemContextActionError.unavailable
            }
        case .revealInFinder:
            guard let url = Self.fileURL(from: payloads),
                  FileManager.default.fileExists(atPath: url.path) else {
                throw ItemContextActionError.unavailable
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .copyOriginal:
            try clipboard.write(payloads: payloads, mode: .original)
        case .copyPlainText:
            try writePlainText(Self.plainText(from: payloads))
        case .copyMarkdownLink:
            guard let url = Self.linkURL(from: payloads) else {
                throw ItemContextActionError.unavailable
            }
            try writePlainText(
                ContentActionTransformer.markdownLink(
                    title: item.displayTitle,
                    urlString: url.absoluteString
                )
            )
        case .copyFilePath:
            guard let url = Self.fileURL(from: payloads) else {
                throw ItemContextActionError.unavailable
            }
            try writePlainText(url.path(percentEncoded: false))
        case .copyCleanText:
            try writePlainText(
                ContentActionTransformer.cleanedText(from: Self.plainText(from: payloads))
            )
        case .copyFirstLine:
            try writePlainText(
                ContentActionTransformer.firstLine(from: Self.plainText(from: payloads))
            )
        case .copyURLs:
            try writePlainText(
                ContentActionTransformer.extractedURLs(from: Self.plainText(from: payloads))
            )
        case .pasteOriginal, .pastePlainText, .pasteFilePath, .quickLook:
            throw ItemContextActionError.unsupportedDispatch
        }
    }

    private func payloads(for item: ClipboardItem) throws -> [NormalizedPayload] {
        try repository.payloads(for: item.id).map {
            NormalizedPayload(itemIndex: $0.itemIndex, type: $0.type, data: $0.data)
        }
    }

    private static func fileURL(from payloads: [NormalizedPayload]) -> URL? {
        for payload in payloads where payload.type == "public.file-url" {
            if let url = URL(dataRepresentation: payload.data, relativeTo: nil),
               url.isFileURL {
                return url.standardizedFileURL
            }
            if let value = String(data: payload.data, encoding: .utf8),
               let url = URL(string: value), url.isFileURL {
                return url.standardizedFileURL
            }
        }

        for payload in payloads where payload.type == "NSFilenamesPboardType" {
            guard let values = try? PropertyListSerialization.propertyList(
                from: payload.data,
                options: [],
                format: nil
            ) as? [String],
            let path = values.first else {
                continue
            }
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return nil
    }

    private static func linkURL(from payloads: [NormalizedPayload]) -> URL? {
        let candidates = payloads.filter { payload in
            payload.type == "public.url" ||
                payload.type == "public.utf8-plain-text" ||
                payload.type == "public.plain-text"
        }
        for payload in candidates {
            guard let value = String(data: payload.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  !value.contains(where: \.isWhitespace),
                  let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme) else {
                continue
            }
            return url
        }
        return nil
    }

    private func writePlainText(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = text.data(using: .utf8) else {
            throw ItemContextActionError.unavailable
        }

        let payload = NormalizedPayload(
            itemIndex: 0,
            type: "public.utf8-plain-text",
            data: data
        )
        try clipboard.write(payloads: [payload], mode: .original)
    }

    private static func plainText(from payloads: [NormalizedPayload]) throws -> String {
        guard let text = SystemClipboard.plainText(from: payloads) else {
            throw ItemContextActionError.unavailable
        }
        return text
    }
}

private enum ItemContextActionError: Error {
    case unavailable
    case unsupportedDispatch
}
