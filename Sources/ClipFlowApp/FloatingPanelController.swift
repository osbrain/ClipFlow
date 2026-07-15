import AppKit
import ClipFlowUI
import SwiftUI

@MainActor
final class FloatingPanelController: NSWindowController, NSWindowDelegate {
    private let frameDefaultsKey = "panelFrame"
    private let minimumPanelSize = NSSize(width: 800, height: 520)
    private let inputState: PanelInputStateStore
    private let frameDefaults: UserDefaults
    private let commandRouter = PanelCommandRouter()
    private let handleCommand: (PanelCommandAction) -> Void
    nonisolated(unsafe) private var eventMonitor: Any?

    init(
        rootView: AnyView,
        inputState: PanelInputStateStore,
        frameDefaults: UserDefaults = .standard,
        handleCommand: @escaping (PanelCommandAction) -> Void
    ) {
        self.inputState = inputState
        self.frameDefaults = frameDefaults
        self.handleCommand = handleCommand
        let initialSize = Self.developmentPanelSize ?? NSSize(width: 1000, height: 680)
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = minimumPanelSize
        panel.contentView = NSHostingView(rootView: rootView)
        super.init(window: panel)
        panel.delegate = self
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let panel = window else { return }
        let screen = Self.frontmostApplicationScreen ?? Self.pointerScreen ?? NSScreen.main
        let desiredFrame = if Self.developmentPanelSize != nil {
            Self.centeredFrame(
                size: panel.frame.size,
                in: screen?.visibleFrame ?? panel.frame
            )
        } else {
            restoredFrame ?? Self.centeredFrame(
                size: panel.frame.size,
                in: screen?.visibleFrame ?? panel.frame
            )
        }
        panel.setFrame(Self.clamp(desiredFrame, to: screen?.visibleFrame), display: false)
        inputState.isPanelVisible = true
        installEventMonitor()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        inputState.isPanelVisible = false
        removeEventMonitor()
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        inputState.isPanelVisible = false
        removeEventMonitor()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard PanelDismissalPolicy.shouldHideOnResign(
            isPresentingSheet: inputState.isPresentingSheet,
            isPresentingOnboarding: inputState.isPresentingOnboarding
        ) else { return }
        hide()
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveFrame()
    }

    private func saveFrame() {
        guard let frame = window?.frame else { return }
        frameDefaults.set(NSStringFromRect(frame), forKey: frameDefaultsKey)
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let panel = self.window,
                  PanelEventRoutingScope.shouldRoute(
                      isPanelKeyWindow: panel.isKeyWindow,
                      eventTargetsPanel: event.window === panel
                  ),
                  let command = Self.command(for: event) else {
                return event
            }
            let action = self.commandRouter.action(
                for: command,
                context: self.inputState.commandContext
            )
            guard action != .passThrough else { return event }
            self.handleCommand(action)
            return nil
        }
    }

    private func removeEventMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private static func command(for event: NSEvent) -> PanelCommand? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 49 where modifiers.isEmpty:
            return PanelCommand.space
        case 36 where modifiers == .command, 76 where modifiers == .command:
            return PanelCommand.commandReturn
        case 36 where modifiers.isEmpty, 76 where modifiers.isEmpty:
            return PanelCommand.returnKey
        case 53 where modifiers.isEmpty:
            return PanelCommand.escape
        case 126 where modifiers.isEmpty:
            return PanelCommand.moveUp
        case 125 where modifiers.isEmpty:
            return PanelCommand.moveDown
        default:
            return nil
        }
    }

    private var restoredFrame: NSRect? {
        guard let value = frameDefaults.string(forKey: frameDefaultsKey) else {
            return nil
        }
        let frame = NSRectFromString(value)
        return frame.width >= minimumPanelSize.width && frame.height >= minimumPanelSize.height
            ? frame
            : nil
    }

    private static var pointerScreen: NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }

    private static var developmentPanelSize: NSSize? {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard let widthValue = environment["CLIPFLOW_WINDOW_WIDTH"],
              let heightValue = environment["CLIPFLOW_WINDOW_HEIGHT"],
              let width = Double(widthValue),
              let height = Double(heightValue) else {
            return nil
        }
        return NSSize(width: max(width, 800), height: max(height, 520))
        #else
        return nil
        #endif
    }

    private static var frontmostApplicationScreen: NSScreen? {
        guard let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]] else {
            return nil
        }

        let applicationWindow = windows
            .filter {
                ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processIdentifier
            }
            .compactMap { window -> CGRect? in
                guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                      let x = (bounds["X"] as? NSNumber)?.doubleValue,
                      let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                      let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                      let height = (bounds["Height"] as? NSNumber)?.doubleValue else {
                    return nil
                }
                return CGRect(x: x, y: y, width: width, height: height)
            }
            .max { $0.width * $0.height < $1.width * $1.height }

        guard let applicationWindow else { return nil }
        return NSScreen.screens.first {
            $0.frame.minX <= applicationWindow.midX && applicationWindow.midX < $0.frame.maxX
        }
    }

    private static func centeredFrame(size: NSSize, in visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func clamp(_ frame: NSRect, to visibleFrame: NSRect?) -> NSRect {
        guard let visibleFrame else { return frame }
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
