import AppKit
import ClipFlowCore
import Foundation

public enum ApplicationAction: String, CaseIterable, Equatable, Hashable, Sendable {
    case openFeishu
    case askDoubao

    public var displayName: String {
        switch self {
        case .openFeishu: "Send to Feishu"
        case .askDoubao: "Ask Doubao"
        }
    }

    public var symbolName: String {
        switch self {
        case .openFeishu: "paperplane"
        case .askDoubao: "sparkles"
        }
    }

    public var bundleIdentifiers: [String] {
        switch self {
        case .openFeishu:
            [
                "com.electron.lark",
                "com.larksuite.Lark",
                "com.larksuite.Feishu",
                "com.bytedance.lark",
                "com.bytedance.feishu"
            ]
        case .askDoubao:
            ["com.bot.pc.doubao"]
        }
    }
}

public struct ApplicationActions: Sendable {
    private let installedBundleIDs: Set<String>
    private let enabledActions: Set<ApplicationAction>

    public init(
        installedBundleIDs: Set<String>,
        enabledActions: Set<ApplicationAction> = Set(ApplicationAction.allCases)
    ) {
        self.installedBundleIDs = installedBundleIDs
        self.enabledActions = enabledActions
    }

    public func available(for payloads: [NormalizedPayload]) -> [ApplicationAction] {
        available(isCompatible: payloads.contains(where: Self.isCompatible))
    }

    public func available(for kind: ClipboardKind) -> [ApplicationAction] {
        available(isCompatible: kind != .unknown)
    }

    private func available(isCompatible: Bool) -> [ApplicationAction] {
        guard isCompatible else { return [] }
        return ApplicationAction.allCases.filter { action in
            enabledActions.contains(action) &&
                !installedBundleIDs.isDisjoint(with: action.bundleIdentifiers)
        }
    }

    private static func isCompatible(_ payload: NormalizedPayload) -> Bool {
        switch payload.type {
        case "public.utf8-plain-text", "public.plain-text",
             "public.utf16-plain-text", "public.utf16-external-plain-text",
             "public.rtf", "public.html", "public.url", "public.file-url",
             "public.png", "public.tiff", "public.jpeg", "public.webp",
             "com.compuserve.gif", "com.adobe.pdf":
            true
        default:
            false
        }
    }
}

public struct ClipboardSnapshot: Equatable, Sendable {
    public let payloads: [NormalizedPayload]

    public init(payloads: [NormalizedPayload]) {
        self.payloads = payloads
    }
}

public protocol ApplicationActionClipboard: Sendable {
    func captureActionSnapshot() throws -> ClipboardSnapshot
    func write(_ payloads: [NormalizedPayload]) throws
    func restore(_ snapshot: ClipboardSnapshot) throws
}

public protocol ApplicationActionLaunching: Sendable {
    func activate(bundleIdentifiers: [String]) async throws
}

public protocol ApplicationActionPastePosting: Sendable {
    func postPaste() throws
}

public enum ApplicationActionError: Error, Equatable, Sendable {
    case targetUnavailable
    case accessibilityRequired
    case pasteboardUnavailable
    case launchFailed(String)
}

extension ApplicationActionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .targetUnavailable: "The target application is not available."
        case .accessibilityRequired: "Accessibility permission is required for automatic paste."
        case .pasteboardUnavailable: "The clipboard is unavailable."
        case .launchFailed(let message): "The target application could not open: \(message)"
        }
    }
}

public struct ApplicationActionRunner: Sendable {
    private let clipboard: any ApplicationActionClipboard
    private let launcher: any ApplicationActionLaunching
    private let pastePoster: any ApplicationActionPastePosting

    public init(
        clipboard: any ApplicationActionClipboard,
        launcher: any ApplicationActionLaunching,
        pastePoster: any ApplicationActionPastePosting
    ) {
        self.clipboard = clipboard
        self.launcher = launcher
        self.pastePoster = pastePoster
    }

    public func perform(
        _ action: ApplicationAction,
        payloads: [NormalizedPayload]
    ) async throws {
        let original = try clipboard.captureActionSnapshot()
        do {
            try clipboard.write(payloads)
            try await launcher.activate(bundleIdentifiers: action.bundleIdentifiers)
            try pastePoster.postPaste()
        } catch {
            try? clipboard.restore(original)
            throw error
        }
    }
}

public struct SystemApplicationActionLauncher: ApplicationActionLaunching {
    public init() {}

    public func activate(bundleIdentifiers: [String]) async throws {
        for bundleIdentifier in bundleIdentifiers {
            if let running = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).first(where: { !$0.isTerminated }) {
                if running.activate(options: []) { return }
            }

            guard let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) else { continue }

            do {
                let application = try await NSWorkspace.shared.openApplication(
                    at: applicationURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
                if application.activate(options: []) { return }
            } catch {
                throw ApplicationActionError.launchFailed(error.localizedDescription)
            }
        }
        throw ApplicationActionError.targetUnavailable
    }
}

public struct SystemApplicationActionPastePoster: ApplicationActionPastePosting {
    private let poster: any AccessibilityPosting

    public init(poster: any AccessibilityPosting = SystemAccessibilityPoster()) {
        self.poster = poster
    }

    public func postPaste() throws {
        guard poster.isTrusted else {
            throw ApplicationActionError.accessibilityRequired
        }
        try poster.postPaste()
    }
}
