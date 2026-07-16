import AppKit
import Testing
@testable import ClipFlowUI

@Suite("Window experience")
@MainActor
struct WindowExperienceTests {
    @Test("main panel width stays within the product range")
    func mainPanelWidthRange() {
        #expect(MainPanelLayout.minimumWidth == 800)
        #expect(MainPanelLayout.idealWidth == 960)
        #expect(MainPanelLayout.maximumWidth == 1_080)
        #expect(MainPanelLayout.clampedWidth(640) == 800)
        #expect(MainPanelLayout.clampedWidth(1_800) == 1_080)
    }

    @Test("header utility controls share one visual height")
    func headerUtilityControlMetrics() {
        #expect(HeaderControlLayout.height == 42)
        #expect(HeaderControlLayout.cornerRadius == 10)
    }

    @Test("main panel hides on focus loss unless a sheet is active")
    func panelDismissalPolicy() {
        #expect(!PanelDismissalPolicy.hidesOnApplicationDeactivate)
        #expect(PanelDismissalPolicy.shouldHideOnResign(isPresentingSheet: false))
        #expect(!PanelDismissalPolicy.shouldHideOnResign(isPresentingSheet: true))
        #expect(
            !PanelDismissalPolicy.shouldHideOnResign(
                isPresentingSheet: false,
                isPresentingOnboarding: true
            )
        )
    }

    @Test("first launch protects onboarding before the panel becomes visible")
    func onboardingStartupState() {
        let state = PanelInputStateStore(isPresentingOnboarding: true)

        #expect(state.isPresentingOnboarding)
        #expect(
            !PanelDismissalPolicy.shouldHideOnResign(
                isPresentingSheet: state.isPresentingSheet,
                isPresentingOnboarding: state.isPresentingOnboarding
            )
        )
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

    @Test("settings window keeps native titlebar controls unobstructed")
    func settingsWindowAppearance() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipFlow Settings"

        SettingsWindowAppearance.apply(to: window)

        #expect(!window.styleMask.contains(.fullSizeContentView))
        #expect(window.title.isEmpty)
        #expect(!window.titlebarAppearsTransparent)
        #expect(window.isOpaque)
        #expect(window.backgroundColor == .windowBackgroundColor)
    }

    @Test("settings window keeps usable traffic lights at a fixed rectangular size")
    func settingsWindowControlsAndSize() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        SettingsWindowAppearance.apply(to: window)

        #expect(SettingsWindowAppearance.contentSize == NSSize(width: 700, height: 700))
        #expect(window.contentMinSize == SettingsWindowAppearance.contentSize)
        #expect(window.contentMaxSize == SettingsWindowAppearance.contentSize)
        #expect(!window.styleMask.contains(.resizable))
        #expect(window.standardWindowButton(.closeButton)?.isEnabled == true)
        #expect(window.standardWindowButton(.closeButton)?.isHidden == false)
        #expect(window.standardWindowButton(.miniaturizeButton)?.isEnabled == true)
        #expect(window.standardWindowButton(.miniaturizeButton)?.isHidden == false)
        #expect(window.standardWindowButton(.zoomButton)?.isHidden == true)
    }

    @Test("accessory settings windows hide when the minimize control is used")
    func accessoryWindowMinimizeBehavior() {
        #expect(
            SettingsWindowMinimizeBehavior.action(
                forAccessoryApplication: true
            ) == .hide
        )
        #expect(
            SettingsWindowMinimizeBehavior.action(
                forAccessoryApplication: false
            ) == .miniaturize
        )
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
