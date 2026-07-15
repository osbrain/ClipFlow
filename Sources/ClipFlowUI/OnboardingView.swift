import AppKit
import SwiftUI

public struct OnboardingView: View {
    @Bindable private var settings: SettingsModel
    private let complete: () -> Void

    public init(settings: SettingsModel, complete: @escaping () -> Void) {
        self.settings = settings
        self.complete = complete
    }

    public var body: some View {
        VStack(spacing: 24) {
            if let icon = ClipFlowBrandIcon.image() {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
            } else {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.blue)
            }
            VStack(spacing: 8) {
                Text(L10n.string("app.name"))
                    .font(.largeTitle.weight(.semibold))
                Text(L10n.string("onboarding.subtitle"))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                permissionRow(
                    icon: "key.fill",
                    title: L10n.string("onboarding.localEncryption"),
                    status: L10n.string("onboarding.enabled"),
                    granted: true
                )
                permissionRow(
                    icon: "hand.raised.fill",
                    title: L10n.string("onboarding.automaticPaste"),
                    status: L10n.string(
                        settings.isAccessibilityTrusted
                            ? "onboarding.granted"
                            : "onboarding.optional"
                    ),
                    granted: settings.isAccessibilityTrusted
                )
            }
            .frame(maxWidth: 430)

            HStack {
                if !settings.isAccessibilityTrusted {
                    Button(L10n.string("onboarding.accessibilitySettings")) {
                        Task {
                            await settings.requestAccessibilityAuthorization()
                            if !settings.isAccessibilityTrusted {
                                Self.openAccessibilitySettings()
                            }
                        }
                    }
                }
                Spacer()
                Button(L10n.string("onboarding.continue"), action: complete)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: 430)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .task { await settings.refreshPermissions() }
    }

    private static func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func permissionRow(
        icon: String,
        title: String,
        status: String,
        granted: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
                .foregroundStyle(granted ? .green : .secondary)
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
    }
}
