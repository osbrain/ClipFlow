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
        #expect(ClipFlowVisualStyle.scrollIndicatorOpacity < 0.6)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        ClipFlowScrollAppearance.apply(to: scrollView)

        #expect(scrollView.scrollerStyle == .overlay)
        #expect(scrollView.autohidesScrollers)
        #expect(scrollView.verticalScroller?.controlSize == .mini)
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
}
