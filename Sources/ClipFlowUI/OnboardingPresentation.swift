import CoreGraphics

public enum OnboardingLayout {
    public static let minimumSize = CGSize(width: 800, height: 520)
    public static let heroWidth: CGFloat = 250
    public static let setupMaximumWidth: CGFloat = 830
}

public struct OnboardingPermissionPresentation: Equatable, Sendable {
    public let isComplete: Bool
    public let statusKey: String
    public let primaryActionKey: String
    public let permissionActionKey: String?

    public init(isTrusted: Bool) {
        isComplete = isTrusted
        statusKey = isTrusted
            ? "onboarding.granted"
            : "onboarding.permission.pending"
        primaryActionKey = isTrusted
            ? "onboarding.getStarted"
            : "onboarding.tryClipFlow"
        permissionActionKey = isTrusted
            ? nil
            : "onboarding.accessibilitySettings"
    }
}
