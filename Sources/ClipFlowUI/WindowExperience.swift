import AppKit
import SwiftUI

public enum PanelDismissalPolicy {
    public static let hidesOnApplicationDeactivate = false

    public static func shouldHideOnResign(
        isPresentingSheet: Bool,
        isPresentingOnboarding: Bool = false
    ) -> Bool {
        !isPresentingSheet && !isPresentingOnboarding
    }
}

@MainActor
public enum SettingsWindowAppearance {
    public static let contentSize = NSSize(width: 700, height: 700)

    public static func apply(to window: NSWindow) {
        window.styleMask.formUnion([.titled, .closable, .miniaturizable])
        window.styleMask.remove(.resizable)
        window.setContentSize(contentSize)
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
        window.standardWindowButton(.closeButton)?.isEnabled = true
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.styleMask.remove(.fullSizeContentView)
        window.title = ""
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.titlebarAppearsTransparent = false
    }
}

public enum SettingsWindowMinimizeBehavior {
    public enum Action: Equatable {
        case hide
        case miniaturize
    }

    public static func action(forAccessoryApplication: Bool) -> Action {
        forAccessoryApplication ? .hide : .miniaturize
    }
}

@MainActor
enum ClipFlowScrollAppearance {
    static func scrollViews(in root: NSView) -> [NSScrollView] {
        var result = (root as? NSScrollView).map { [$0] } ?? []
        for subview in root.subviews {
            result.append(contentsOf: scrollViews(in: subview))
        }
        return result
    }

    static func apply(to root: NSView) {
        for scrollView in scrollViews(in: root) {
            apply(to: scrollView)
        }
    }

    static func apply(to scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        if scrollView.verticalScroller != nil,
           !(scrollView.verticalScroller is ClipFlowOverlayScroller) {
            scrollView.verticalScroller = ClipFlowOverlayScroller()
        }
        if scrollView.horizontalScroller != nil,
           !(scrollView.horizontalScroller is ClipFlowOverlayScroller) {
            scrollView.horizontalScroller = ClipFlowOverlayScroller()
        }
        scrollView.scrollerStyle = .overlay
        for scroller in [scrollView.verticalScroller, scrollView.horizontalScroller] {
            scroller?.controlSize = .mini
            scroller?.scrollerStyle = .overlay
            scroller?.alphaValue = 1
        }
    }

    static func indicatorRect(in knobRect: CGRect) -> CGRect {
        let thickness = min(
            ClipFlowVisualStyle.scrollIndicatorThickness,
            min(knobRect.width, knobRect.height)
        )
        guard thickness > 0 else { return .zero }

        if knobRect.height >= knobRect.width {
            return CGRect(
                x: knobRect.midX - thickness / 2,
                y: knobRect.minY + 1,
                width: thickness,
                height: max(0, knobRect.height - 2)
            )
        }
        return CGRect(
            x: knobRect.minX + 1,
            y: knobRect.midY - thickness / 2,
            width: max(0, knobRect.width - 2),
            height: thickness
        )
    }
}

@MainActor
final class ClipFlowOverlayScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool {
        self == ClipFlowOverlayScroller.self
    }

    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat {
        scrollerStyle == .overlay
            ? 5
            : super.scrollerWidth(
                for: controlSize,
                scrollerStyle: scrollerStyle
            )
    }

    private var isPointerInside = false
    private var pointerTrackingArea: NSTrackingArea?

    override func drawKnob() {
        let indicatorRect = ClipFlowScrollAppearance.indicatorRect(
            in: rect(for: .knob)
        )
        guard !indicatorRect.isEmpty else { return }

        let opacity = isPointerInside || isHighlighted
            ? ClipFlowVisualStyle.scrollIndicatorHoverOpacity
            : ClipFlowVisualStyle.scrollIndicatorOpacity
        NSColor.secondaryLabelColor.withAlphaComponent(opacity).setFill()
        NSBezierPath(
            roundedRect: indicatorRect,
            xRadius: ClipFlowVisualStyle.scrollIndicatorThickness / 2,
            yRadius: ClipFlowVisualStyle.scrollIndicatorThickness / 2
        ).fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func updateTrackingAreas() {
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let nextTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(nextTrackingArea)
        pointerTrackingArea = nextTrackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        needsDisplay = true
    }
}

extension View {
    func clipFlowScrollAppearance() -> some View {
        background(ClipFlowScrollProbe().frame(width: 0, height: 0))
    }
}

private struct ClipFlowScrollProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.scheduleConfiguration()
    }

    final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleConfiguration()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleConfiguration()
        }

        func scheduleConfiguration() {
            DispatchQueue.main.async { [weak self] in
                guard let contentView = self?.window?.contentView else { return }
                ClipFlowScrollAppearance.apply(to: contentView)
            }
        }
    }
}
