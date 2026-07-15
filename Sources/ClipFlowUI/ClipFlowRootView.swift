import Foundation
import SwiftUI

public struct ClipFlowRootView: View {
    @AppStorage private var hasCompletedOnboarding: Bool
    private let model: AppModel
    private let settings: SettingsModel
    private let browserModel: BrowserTabModel?
    private let inputState: PanelInputStateStore
    private let showSettings: () -> Void

    public init(
        model: AppModel,
        settings: SettingsModel,
        browserModel: BrowserTabModel? = nil,
        inputState: PanelInputStateStore = PanelInputStateStore(),
        userDefaults: UserDefaults = .standard,
        showSettings: @escaping () -> Void = {}
    ) {
        _hasCompletedOnboarding = AppStorage(
            wrappedValue: false,
            "hasCompletedOnboarding",
            store: userDefaults
        )
        self.model = model
        self.settings = settings
        self.browserModel = browserModel
        self.inputState = inputState
        self.showSettings = showSettings
    }

    public var body: some View {
        rootContent
            .preferredColorScheme(settings.appearanceMode.colorScheme)
            .id(settings.appLanguage)
            .environment(\.locale, L10n.locale)
    }

    @ViewBuilder
    private var rootContent: some View {
        if hasCompletedOnboarding {
            MainPanelView(
                model: model,
                settings: settings,
                browserModel: settings.browserTabManagementEnabled ? browserModel : nil,
                inputState: inputState,
                showSettings: showSettings
            )
        } else {
            OnboardingView(settings: settings, inputState: inputState) {
                hasCompletedOnboarding = true
            }
        }
    }
}
