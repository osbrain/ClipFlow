import Foundation
import Testing
import ClipFlowCore
@testable import ClipFlowSystem

@Suite("Preview drag and application actions")
struct ApplicationActionsTests {
    @Test("requires an installed enabled target and compatible content")
    func actionAvailabilityIsGuarded() {
        let text = [Self.payload("public.utf8-plain-text", "hello")]
        let binary = [NormalizedPayload(
            itemIndex: 0,
            type: "com.example.binary",
            data: Data([0x00, 0x01])
        )]
        let actions = ApplicationActions(
            installedBundleIDs: ["com.larksuite.Feishu"],
            enabledActions: [.openFeishu, .askDoubao]
        )

        #expect(actions.available(for: text).contains(.openFeishu))
        #expect(!actions.available(for: binary).contains(.openFeishu))
        #expect(!actions.available(for: text).contains(.askDoubao))
        #expect(actions.available(for: ClipboardKind.text).contains(.openFeishu))
        #expect(actions.available(for: ClipboardKind.unknown).isEmpty)

        let disabled = ApplicationActions(
            installedBundleIDs: ["com.larksuite.Feishu"],
            enabledActions: []
        )
        #expect(disabled.available(for: text).isEmpty)
    }

    @Test("restores the original clipboard when target activation fails")
    func failedActionRestoresClipboard() async {
        let original = ClipboardSnapshot(payloads: [Self.payload("public.utf8-plain-text", "before")])
        let clipboard = FakeActionClipboard(snapshot: original)
        let runner = ApplicationActionRunner(
            clipboard: clipboard,
            launcher: FailingActionLauncher(),
            pastePoster: SuccessfulPastePoster()
        )

        await #expect(throws: ApplicationActionError.targetUnavailable) {
            try await runner.perform(
                .askDoubao,
                payloads: [Self.payload("public.utf8-plain-text", "question")]
            )
        }
        #expect(clipboard.restoredSnapshots == [original])
    }

    @Test("materializes supported payloads and removes temporary previews")
    func previewTemporaryFileLifecycle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = PreviewService(root: root)

        let artifact = try service.prepare(
            payloads: [NormalizedPayload(
                itemIndex: 0,
                type: "public.png",
                data: Data([0x89, 0x50, 0x4e, 0x47])
            )],
            suggestedName: "Screenshot"
        )

        #expect(artifact.isTemporary)
        #expect(artifact.url.pathExtension == "png")
        #expect(FileManager.default.fileExists(atPath: artifact.url.path))
        #expect(try Data(contentsOf: artifact.url) == Data([0x89, 0x50, 0x4e, 0x47]))
        let attributes = try FileManager.default.attributesOfItem(atPath: artifact.url.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)
        try service.cleanup(artifact)
        #expect(!FileManager.default.fileExists(atPath: artifact.url.path))
    }

    @MainActor
    @Test("Quick Look controller presents an owned preview window")
    func quickLookControllerPresentsOwnedWindow() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = QuickLookPreviewController(
            service: PreviewService(root: root)
        )

        try controller.show(
            payloads: [Self.payload("public.utf8-plain-text", "Preview body")],
            suggestedName: "Preview Fixture"
        )

        #expect(controller.isPreviewVisible)
        #expect(controller.previewWindowTitle == "Preview Fixture")
        controller.close()
        #expect(!controller.isPreviewVisible)
    }

    @Test("uses an existing file directly for preview and drag")
    func existingFileIsNotCopied() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipflow-\(UUID().uuidString).txt")
        try Data("document".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let payloads = [Self.payload("public.file-url", file.absoluteString)]
        let preview = PreviewService(root: FileManager.default.temporaryDirectory)
        let dragWriter = ClipboardDragWriter()

        let artifact = try preview.prepare(payloads: payloads, suggestedName: "Document")
        #expect(artifact.url == file)
        #expect(!artifact.isTemporary)
        #expect(try dragWriter.representation(
            for: payloads,
            suggestedName: "Document"
        ) == .fileURL(file))
    }

    @Test("creates a promised file for non-file drag content")
    func createsPromisedDragFile() throws {
        let writer = ClipboardDragWriter()

        let representation = try writer.representation(
            for: [Self.payload("public.utf8-plain-text", "hello")],
            suggestedName: "Greeting"
        )

        #expect(representation == .promisedFile(
            fileName: "Greeting.txt",
            typeIdentifier: "public.utf8-plain-text",
            data: Data("hello".utf8)
        ))
    }

    private static func payload(_ type: String, _ string: String) -> NormalizedPayload {
        NormalizedPayload(itemIndex: 0, type: type, data: Data(string.utf8))
    }
}

private final class FakeActionClipboard: ApplicationActionClipboard, @unchecked Sendable {
    private let lock = NSLock()
    private let storedSnapshot: ClipboardSnapshot
    private var restorations: [ClipboardSnapshot] = []

    init(snapshot: ClipboardSnapshot) {
        storedSnapshot = snapshot
    }

    var restoredSnapshots: [ClipboardSnapshot] {
        lock.withLock { restorations }
    }

    func captureActionSnapshot() throws -> ClipboardSnapshot {
        storedSnapshot
    }

    func write(_ payloads: [NormalizedPayload]) throws {}

    func restore(_ snapshot: ClipboardSnapshot) throws {
        lock.withLock { restorations.append(snapshot) }
    }
}

private struct FailingActionLauncher: ApplicationActionLaunching {
    func activate(bundleIdentifiers: [String]) async throws {
        throw ApplicationActionError.targetUnavailable
    }
}

private struct SuccessfulPastePoster: ApplicationActionPastePosting {
    func postPaste() throws {}
}
