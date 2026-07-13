import SwiftUI

public enum ClipFlowAppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

public enum ClipFlowListDensity: String, CaseIterable, Sendable {
    case comfortable
    case compact

    public var rowHeight: CGFloat {
        switch self {
        case .comfortable: 74
        case .compact: 62
        }
    }
}
