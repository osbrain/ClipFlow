import AppKit
import SwiftUI

public enum PanelDismissalPolicy {
    public static func shouldHideOnResign(isPresentingSheet: Bool) -> Bool {
        !isPresentingSheet
    }
}

@MainActor
public enum SettingsWindowAppearance {
    public static func apply(to window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.titlebarAppearsTransparent = true
    }
}

@MainActor
enum ClipFlowScrollAppearance {
    static func apply(to scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        for scroller in [scrollView.verticalScroller, scrollView.horizontalScroller] {
            scroller?.controlSize = .mini
            scroller?.alphaValue = ClipFlowVisualStyle.scrollIndicatorOpacity
        }
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
                guard let scrollView = self?.enclosingScrollView else { return }
                ClipFlowScrollAppearance.apply(to: scrollView)
            }
        }
    }
}
