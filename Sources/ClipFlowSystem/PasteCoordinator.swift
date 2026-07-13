import AppKit
import ApplicationServices
import ClipFlowCore
import Foundation

public struct PasteRequest: Equatable, Sendable {
    public let payloads: [NormalizedPayload]
    public let mode: PasteMode

    public init(payloads: [NormalizedPayload], mode: PasteMode) {
        self.payloads = payloads
        self.mode = mode
    }
}

public struct PasteTarget: Equatable, Sendable {
    public let processIdentifier: Int32
    public let bundleID: String?

    public init(processIdentifier: Int32, bundleID: String?) {
        self.processIdentifier = processIdentifier
        self.bundleID = bundleID
    }
}

public enum PasteOutcome: Equatable, Sendable {
    case pasted
    case copiedRequiresManualPaste
}

public protocol ClipboardWriting: Sendable {
    @discardableResult
    func write(payloads: [NormalizedPayload], mode: PasteMode) throws -> Int
}

public protocol AccessibilityPosting: Sendable {
    var isTrusted: Bool { get }
    func postPaste() throws
}

public protocol ApplicationActivating: Sendable {
    func activate(_ target: PasteTarget) async -> Bool
}

public struct PasteCoordinator: Sendable {
    private let writer: any ClipboardWriting
    private let accessibility: any AccessibilityPosting
    private let activator: any ApplicationActivating

    public init(
        writer: any ClipboardWriting,
        accessibility: any AccessibilityPosting,
        activator: any ApplicationActivating
    ) {
        self.writer = writer
        self.accessibility = accessibility
        self.activator = activator
    }

    public func paste(_ request: PasteRequest, target: PasteTarget) async throws -> PasteOutcome {
        try writer.write(payloads: request.payloads, mode: request.mode)
        let activated = await activator.activate(target)

        guard activated, accessibility.isTrusted else {
            return .copiedRequiresManualPaste
        }

        try accessibility.postPaste()
        return .pasted
    }
}

public struct SystemAccessibilityPoster: AccessibilityPosting {
    public init() {}

    public var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    public func postPaste() throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw PasteSystemError.eventCreationFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

public struct SystemApplicationActivator: ApplicationActivating {
    public init() {}

    public func activate(_ target: PasteTarget) async -> Bool {
        guard let application = NSRunningApplication(
            processIdentifier: pid_t(target.processIdentifier)
        ) else {
            return false
        }
        return application.activate(options: [.activateIgnoringOtherApps])
    }
}

public enum PasteSystemError: Error, Equatable, Sendable {
    case eventCreationFailed
    case pasteboardWriteFailed
    case noPlainTextRepresentation
}

