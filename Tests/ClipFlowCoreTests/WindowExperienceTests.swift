import AppKit
import Testing
@testable import ClipFlowUI

@Suite("Window experience")
@MainActor
struct WindowExperienceTests {
    @Test("main panel hides on focus loss unless a sheet is active")
    func panelDismissalPolicy() {
        #expect(PanelDismissalPolicy.shouldHideOnResign(isPresentingSheet: false))
        #expect(!PanelDismissalPolicy.shouldHideOnResign(isPresentingSheet: true))
    }

    @Test("window and scroll appearance use compact product metrics")
    func productWindowMetrics() {
        #expect(ClipFlowVisualStyle.windowRadius == 18)
        #expect(ClipFlowVisualStyle.primaryActionHeight == 42)
        #expect(ClipFlowVisualStyle.secondaryActionHeight == 36)
        #expect(ClipFlowVisualStyle.utilityActionHeight == 30)
        #expect(ClipFlowVisualStyle.scrollIndicatorThickness == 4)
        #expect(ClipFlowVisualStyle.scrollIndicatorOpacity == 0.20)
        #expect(ClipFlowVisualStyle.scrollIndicatorHoverOpacity == 0.34)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        ClipFlowScrollAppearance.apply(to: scrollView)

        #expect(scrollView.scrollerStyle == .overlay)
        #expect(scrollView.autohidesScrollers)
        #expect(scrollView.verticalScroller?.controlSize == .mini)
        #expect(scrollView.verticalScroller is ClipFlowOverlayScroller)
        #expect(scrollView.verticalScroller?.scrollerStyle == .overlay)
        #expect(
            ClipFlowOverlayScroller.scrollerWidth(
                for: .mini,
                scrollerStyle: .overlay
            ) == 7
        )
    }

    @Test("settings material extends behind its transparent title bar")
    func settingsWindowAppearance() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        SettingsWindowAppearance.apply(to: window)

        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titlebarAppearsTransparent)
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)
    }

    @Test("overlay scroll indicators stay four points thick in both orientations")
    func overlayScrollIndicatorGeometry() {
        let verticalKnob = CGRect(x: 0, y: 8, width: 12, height: 72)
        let verticalIndicator = ClipFlowScrollAppearance.indicatorRect(
            in: verticalKnob
        )
        #expect(verticalIndicator.width == 4)
        #expect(verticalIndicator.midX == verticalKnob.midX)

        let horizontalKnob = CGRect(x: 8, y: 0, width: 72, height: 12)
        let horizontalIndicator = ClipFlowScrollAppearance.indicatorRect(
            in: horizontalKnob
        )
        #expect(horizontalIndicator.height == 4)
        #expect(horizontalIndicator.midY == horizontalKnob.midY)
    }
}
