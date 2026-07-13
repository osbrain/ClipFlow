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
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(.blue)
            VStack(spacing: 8) {
                Text("ClipFlow")
                    .font(.largeTitle.weight(.semibold))
                Text("Clipboard history stays encrypted on this Mac.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                permissionRow(
                    icon: "key.fill",
                    title: "Local encryption",
                    status: "Enabled",
                    granted: true
                )
                permissionRow(
                    icon: "hand.raised.fill",
                    title: "Automatic paste",
                    status: settings.isAccessibilityTrusted ? "Granted" : "Optional",
                    granted: settings.isAccessibilityTrusted
                )
            }
            .frame(maxWidth: 430)

            HStack {
                if !settings.isAccessibilityTrusted {
                    Button("Accessibility Settings") {
                        guard let url = URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                        ) else { return }
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
                Button("Continue", action: complete)
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
