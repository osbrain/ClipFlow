import ClipFlowCore
import Foundation

public protocol PasteboardAccess: Sendable {
    var changeCount: Int { get }
    func snapshot() -> RawClipboardCapture?
}

public actor PasteboardMonitor {
    public typealias CaptureHandler = @Sendable (RawClipboardCapture) async -> Void

    private let pasteboard: any PasteboardAccess
    private let interval: Duration
    private var lastChangeCount: Int
    private var ignoredChangeCount: Int?
    private var isPaused = false
    private var monitoringTask: Task<Void, Never>?

    public init(pasteboard: any PasteboardAccess, interval: Duration = .milliseconds(250)) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.lastChangeCount = pasteboard.changeCount
    }

    public func start(handler: @escaping CaptureHandler) {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [weak self] in
            await self?.monitor(handler: handler)
        }
    }

    public func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    public func pause() {
        isPaused = true
    }

    public func resume() {
        lastChangeCount = pasteboard.changeCount
        isPaused = false
    }

    public func ignoreNextChange(expectedChangeCount: Int) {
        ignoredChangeCount = expectedChangeCount
    }

    private func monitor(handler: @escaping CaptureHandler) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            await pollOnce(handler: handler)
        }
    }

    func pollOnce(handler: @escaping CaptureHandler) async {
        guard !isPaused else { return }
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        if ignoredChangeCount == currentChangeCount {
            ignoredChangeCount = nil
            return
        }
        ignoredChangeCount = nil

        if let capture = pasteboard.snapshot() {
            await handler(capture)
        }
    }
}
