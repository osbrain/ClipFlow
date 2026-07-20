import Foundation
import Testing
import ClipFlowCore
@testable import ClipFlowSystem

@Suite("System clipboard plain text conversion")
struct SystemClipboardPlainTextTests {
    @Test("file URL plain text is a percent-decoded filesystem path")
    func fileURLBecomesFilesystemPath() throws {
        let fileURL = URL(fileURLWithPath: "/Users/Clip Flow/My File.txt")
        let payload = NormalizedPayload(
            itemIndex: 0,
            type: "public.file-url",
            data: fileURL.dataRepresentation
        )

        #expect(SystemClipboard.plainText(from: [payload]) == "/Users/Clip Flow/My File.txt")
    }

    @Test("Finder filename lists become filesystem paths")
    func finderFilenameListBecomesFilesystemPath() throws {
        let payload = NormalizedPayload(
            itemIndex: 0,
            type: "NSFilenamesPboardType",
            data: try PropertyListSerialization.data(
                fromPropertyList: ["/Users/Clip Flow/My File.txt"],
                format: .binary,
                options: 0
            )
        )

        #expect(SystemClipboard.plainText(from: [payload]) == "/Users/Clip Flow/My File.txt")
    }

    @Test("web URLs remain URL text")
    func webURLRemainsURLText() {
        let value = "https://example.com/a%20path"
        let payload = NormalizedPayload(
            itemIndex: 0,
            type: "public.url",
            data: Data(value.utf8)
        )

        #expect(SystemClipboard.plainText(from: [payload]) == value)
    }
}

@Suite("Paste mode resolution")
struct PasteModeResolverTests {
    @Test("per-application preference overrides the default")
    func perApplicationModeOverridesDefault() {
        let resolver = PasteModeResolver(
            defaultMode: .original,
            overrides: ["com.apple.Terminal": .plainText]
        )

        #expect(resolver.mode(for: "com.apple.Terminal") == .plainText)
        #expect(resolver.mode(for: "com.apple.TextEdit") == .original)
    }

    @Test("default paste mode can change without losing application overrides")
    func updatesDefaultModeAtRuntime() {
        let resolver = PasteModeResolver(
            defaultMode: .original,
            overrides: ["com.apple.Terminal": .plainText]
        )

        resolver.updateDefaultMode(.plainText)

        #expect(resolver.mode(for: "com.apple.TextEdit") == .plainText)
        #expect(resolver.mode(for: "com.apple.Terminal") == .plainText)
    }
}

@Suite("Paste coordination")
struct PasteCoordinatorTests {
    @Test("writes the clipboard when Accessibility is denied")
    func writesClipboardWhenAccessibilityIsDenied() async throws {
        let writer = FakeClipboardWriter()
        let activator = FakeApplicationActivator()
        let coordinator = PasteCoordinator(
            writer: writer,
            accessibility: FakeAccessibility(isTrusted: false),
            activator: activator
        )
        let request = PasteRequest(
            payloads: [
                NormalizedPayload(
                    itemIndex: 0,
                    type: "public.utf8-plain-text",
                    data: Data("hello".utf8)
                )
            ],
            mode: .original
        )

        let outcome = try await coordinator.paste(
            request,
            target: PasteTarget(processIdentifier: 42, bundleID: "com.apple.TextEdit")
        )

        #expect(writer.lastText == "hello")
        #expect(outcome == .copiedRequiresManualPaste)
        #expect(activator.activationCount == 0)
    }
}

private final class FakeClipboardWriter: ClipboardWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var text: String?

    var lastText: String? { lock.withLock { text } }

    func write(payloads: [NormalizedPayload], mode: PasteMode) throws -> Int {
        lock.withLock {
            text = payloads.first.flatMap { String(data: $0.data, encoding: .utf8) }
        }
        return 2
    }
}

private struct FakeAccessibility: AccessibilityPosting {
    let isTrusted: Bool
    func postPaste() throws {}
}

private final class FakeApplicationActivator: ApplicationActivating, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var activationCount: Int { lock.withLock { count } }

    func activate(_ target: PasteTarget) async -> Bool {
        lock.withLock { count += 1 }
        return true
    }
}
