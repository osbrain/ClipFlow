import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController: NSWindowController, NSWindowDelegate {
    private let frameDefaultsKey = "panelFrame"
    private let minimumPanelSize = NSSize(width: 760, height: 480)

    init(rootView: AnyView) {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
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
        let desiredFrame = restoredFrame ?? Self.centeredFrame(
            size: panel.frame.size,
            in: screen?.visibleFrame ?? panel.frame
        )
        panel.setFrame(Self.clamp(desiredFrame, to: screen?.visibleFrame), display: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveFrame()
    }

    private func saveFrame() {
        guard let frame = window?.frame else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: frameDefaultsKey)
    }

    private var restoredFrame: NSRect? {
        guard let value = UserDefaults.standard.string(forKey: frameDefaultsKey) else {
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
