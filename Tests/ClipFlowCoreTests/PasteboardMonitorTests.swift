import Foundation
import Testing
import ClipFlowCore
@testable import ClipFlowSystem

@Suite("Pasteboard monitoring")
struct PasteboardMonitorTests {
    @Test("emits once per change and ignores an expected internal write")
    func emitsOnceAndIgnoresInternalWrite() async throws {
        let board = FakePasteboard(changeCount: 1)
        let recorder = CaptureRecorder()
        let monitor = PasteboardMonitor(
            pasteboard: board,
            interval: .milliseconds(10)
        )

        board.setText("first", changeCount: 2)
        await monitor.pollOnce { capture in
            await recorder.append(capture)
        }

        await monitor.ignoreNextChange(expectedChangeCount: 3)
        board.setText("internal", changeCount: 3)
        await monitor.pollOnce { capture in
            await recorder.append(capture)
        }

        #expect(await recorder.count == 1)
        #expect(await recorder.lastText == "first")
    }
}

private final class FakePasteboard: PasteboardAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var storedChangeCount: Int
    private var text = ""

    init(changeCount: Int) {
        storedChangeCount = changeCount
    }

    var changeCount: Int {
        lock.withLock { storedChangeCount }
    }

    func snapshot() -> RawClipboardCapture? {
        lock.withLock {
            RawClipboardCapture(
                sourceAppName: "Test",
                sourceBundleID: "local.clipflow.tests",
                items: [
                    RawClipboardItem(representations: [
                        RawClipboardRepresentation(
                            type: "public.utf8-plain-text",
                            data: Data(text.utf8)
                        )
                    ])
                ]
            )
        }
    }

    func setText(_ value: String, changeCount: Int) {
        lock.withLock {
            text = value
            storedChangeCount = changeCount
        }
    }
}

private actor CaptureRecorder {
    private var values: [RawClipboardCapture] = []

    var count: Int { values.count }

    var lastText: String? {
        guard let data = values.last?.items.first?.representations.first?.data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func append(_ capture: RawClipboardCapture) {
        values.append(capture)
    }
}
