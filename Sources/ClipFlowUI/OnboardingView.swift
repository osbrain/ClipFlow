import AppKit
import SwiftUI

public struct OnboardingView: View {
    @Bindable private var settings: SettingsModel
    private let inputState: PanelInputStateStore
    private let complete: () -> Void

    public init(
        settings: SettingsModel,
        inputState: PanelInputStateStore,
        complete: @escaping () -> Void
    ) {
        self.settings = settings
        self.inputState = inputState
        self.complete = complete
    }

    public var body: some View {
        HStack(spacing: 0) {
            hero
                .frame(width: OnboardingLayout.heroBackgroundMinimumSize.width)
                .frame(
                    minHeight: OnboardingLayout.heroBackgroundMinimumSize.height,
                    maxHeight: .infinity
                )
                .background { heroBackground }

            Divider()

            setup
                .frame(maxWidth: OnboardingLayout.setupMaximumWidth)
        }
        .frame(
            minWidth: OnboardingLayout.minimumSize.width,
            minHeight: OnboardingLayout.minimumSize.height
        )
        .background(.regularMaterial)
        .task {
            await settings.refreshPermissions()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await settings.refreshPermissions()
            }
        }
        .onAppear { inputState.isPresentingOnboarding = true }
        .onDisappear { inputState.isPresentingOnboarding = false }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                brandIcon
                    .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.string("onboarding.welcome"))
                        .font(.title2.weight(.bold))
                    Text(L10n.string("onboarding.value"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 13) {
                feature(icon: "magnifyingglass", key: "onboarding.feature.search")
                feature(icon: "arrow.right.circle", key: "onboarding.feature.paste")
                feature(icon: "keyboard", key: "onboarding.feature.keyboard")
            }

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("onboarding.shortcut.caption"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(shortcutDisplayName)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(ClipFlowVisualStyle.hairlineColor)
                    }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
    }

    private var heroBackground: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.15),
                Color.accentColor.opacity(0.045)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var setup: some View {
        let permission = OnboardingPermissionPresentation(
            isTrusted: settings.isAccessibilityTrusted
        )

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.string("onboarding.setup.title"))
                        .font(.title2.weight(.semibold))
                    Text(L10n.string("onboarding.setup.subtitle"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                Text(L10n.string("onboarding.setup.duration"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
            }

            VStack(spacing: 10) {
                setupRow(
                    icon: "lock.shield.fill",
                    titleKey: "onboarding.localEncryption",
                    descriptionKey: "onboarding.localEncryption.description",
                    isComplete: true
                ) {
                    statusLabel(L10n.string("onboarding.enabled"), complete: true)
                }

                setupRow(
                    icon: permission.isComplete
                        ? "checkmark.circle.fill"
                        : "hand.raised.fill",
                    titleKey: "onboarding.automaticPaste",
                    descriptionKey: "onboarding.automaticPaste.description",
                    isComplete: permission.isComplete,
                    emphasized: !permission.isComplete
                ) {
                    if let actionKey = permission.permissionActionKey {
                        Button(L10n.string(actionKey)) {
                            requestAccessibilityAuthorization()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help(L10n.string("onboarding.automaticPaste.description"))
                    } else {
                        statusLabel(L10n.string(permission.statusKey), complete: true)
                    }
                }

                setupRow(
                    icon: "command",
                    titleKey: "onboarding.shortcut.title",
                    descriptionKey: "onboarding.shortcut.description",
                    isComplete: true
                ) {
                    statusLabel(shortcutDisplayName, complete: true)
                }
            }

            Label(
                L10n.string("onboarding.permission.privacy"),
                systemImage: "lock.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 9) {
                Label(
                    L10n.string("onboarding.quickStart.title"),
                    systemImage: "bolt.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    quickStartStep(number: 1, text: L10n.string("onboarding.quickStart.copy"))
                    quickStartConnector
                    quickStartStep(
                        number: 2,
                        text: L10n.format("onboarding.quickStart.open", shortcutDisplayName)
                    )
                    quickStartConnector
                    quickStartStep(number: 3, text: L10n.string("onboarding.quickStart.paste"))
                }
            }
            .padding(11)
            .background(Color.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(ClipFlowVisualStyle.hairlineColor)
            }

            Spacer(minLength: 4)

            HStack(spacing: 10) {
                Spacer(minLength: 0)

                if !permission.isComplete {
                    Button(L10n.string("onboarding.notNow"), action: complete)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }

                Button(L10n.string(permission.primaryActionKey), action: complete)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func setupRow<Accessory: View>(
        icon: String,
        titleKey: String,
        descriptionKey: String,
        isComplete: Bool,
        emphasized: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isComplete ? Color.green : Color.accentColor)
                .frame(width: 36, height: 36)
                .background(
                    (isComplete ? Color.green : Color.accentColor).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(titleKey))
                    .font(.callout.weight(.semibold))
                Text(L10n.string(descriptionKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 10)
            accessory()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 62)
        .background(
            emphasized
                ? Color.accentColor.opacity(0.09)
                : Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    emphasized
                        ? Color.accentColor.opacity(0.34)
                        : ClipFlowVisualStyle.hairlineColor
                )
        }
    }

    private func statusLabel(_ text: String, complete: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(complete ? .primary : .secondary)
            .lineLimit(1)
    }

    private func feature(icon: String, key: String) -> some View {
        Label {
            Text(L10n.string(key))
                .font(.callout.weight(.medium))
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 25, height: 25)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private func quickStartStep(number: Int, text: String) -> some View {
        HStack(spacing: 6) {
            Text(number, format: .number)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickStartConnector: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var brandIcon: some View {
        if let icon = ClipFlowBrandIcon.image() {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
    }

    private var shortcutDisplayName: String {
        L10n.string("settings.shortcut.\(settings.shortcut.rawValue)")
    }

    private func requestAccessibilityAuthorization() {
        Task {
            await settings.requestAccessibilityAuthorization()
            if !settings.isAccessibilityTrusted {
                Self.openAccessibilitySettings()
            }
        }
    }

    private static func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
