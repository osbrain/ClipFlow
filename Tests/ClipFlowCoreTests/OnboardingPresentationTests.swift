import CoreGraphics
import Testing
@testable import ClipFlowUI

@Suite("Onboarding presentation")
struct OnboardingPresentationTests {
    @Test("onboarding fills the supported compact panel")
    func compactPanelMetrics() {
        #expect(OnboardingLayout.minimumSize == CGSize(width: 800, height: 520))
        #expect(OnboardingLayout.heroWidth == 250)
        #expect(OnboardingLayout.setupMaximumWidth == 830)
    }

    @Test("pending permission keeps onboarding optional and actionable")
    func pendingPermissionPresentation() {
        let presentation = OnboardingPermissionPresentation(isTrusted: false)

        #expect(!presentation.isComplete)
        #expect(presentation.statusKey == "onboarding.permission.pending")
        #expect(presentation.primaryActionKey == "onboarding.tryClipFlow")
        #expect(presentation.permissionActionKey == "onboarding.accessibilitySettings")
    }

    @Test("granted permission promotes the completed onboarding action")
    func grantedPermissionPresentation() {
        let presentation = OnboardingPermissionPresentation(isTrusted: true)

        #expect(presentation.isComplete)
        #expect(presentation.statusKey == "onboarding.granted")
        #expect(presentation.primaryActionKey == "onboarding.getStarted")
        #expect(presentation.permissionActionKey == nil)
    }
}
