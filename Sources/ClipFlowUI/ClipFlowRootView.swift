import SwiftUI

public struct ClipFlowRootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    private let model: AppModel
    private let settings: SettingsModel
    private let browserModel: BrowserTabModel?

    public init(
        model: AppModel,
        settings: SettingsModel,
        browserModel: BrowserTabModel? = nil
    ) {
        self.model = model
        self.settings = settings
        self.browserModel = browserModel
    }

    public var body: some View {
        rootContent
            .preferredColorScheme(settings.appearanceMode.colorScheme)
    }

    @ViewBuilder
    private var rootContent: some View {
        if hasCompletedOnboarding {
            MainPanelView(
                model: model,
                browserModel: settings.browserTabManagementEnabled ? browserModel : nil
            )
        } else {
            OnboardingView(settings: settings) {
                hasCompletedOnboarding = true
            }
        }
    }
}
