import SwiftUI

public struct ClipFlowRootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    private let model: AppModel
    private let settings: SettingsModel

    public init(model: AppModel, settings: SettingsModel) {
        self.model = model
        self.settings = settings
    }

    public var body: some View {
        if hasCompletedOnboarding {
            MainPanelView(model: model)
        } else {
            OnboardingView(settings: settings) {
                hasCompletedOnboarding = true
            }
        }
    }
}
