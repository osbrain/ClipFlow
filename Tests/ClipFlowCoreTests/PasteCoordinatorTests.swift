import Foundation
import Testing
import ClipFlowCore
@testable import ClipFlowSystem

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
}

@Suite("Paste coordination")
struct PasteCoordinatorTests {
    @Test("writes the clipboard when Accessibility is denied")
    func writesClipboardWhenAccessibilityIsDenied() async throws {
        let writer = FakeClipboardWriter()
        let coordinator = PasteCoordinator(
            writer: writer,
            accessibility: FakeAccessibility(isTrusted: false),
            activator: FakeApplicationActivator()
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

private struct FakeApplicationActivator: ApplicationActivating {
    func activate(_ target: PasteTarget) async -> Bool { true }
}
