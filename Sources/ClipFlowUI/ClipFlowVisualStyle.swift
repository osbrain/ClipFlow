import SwiftUI

public enum MainPanelLayout {
    public static let minimumWidth: CGFloat = 800
    public static let idealWidth: CGFloat = 960
    public static let maximumWidth: CGFloat = 1_080
    public static let minimumHeight: CGFloat = 520

    public static func clampedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minimumWidth), maximumWidth)
    }
}

enum ClipFlowVisualStyle {
    static let windowRadius: CGFloat = 18
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 9
    static let hairlineOpacity = 0.16
    static let selectedFillOpacity = 0.18
    static let selectedBorderOpacity = 0.9
    static let panelPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 16
    static let primaryActionHeight: CGFloat = 42
    static let secondaryActionHeight: CGFloat = 36
    static let utilityActionHeight: CGFloat = 30
    static let scrollIndicatorThickness: CGFloat = 4
    static let scrollIndicatorOpacity: CGFloat = 0.20
    static let scrollIndicatorHoverOpacity: CGFloat = 0.34
    static let hairlineColor = Color(nsColor: .separatorColor)
    static let hoverFillColor = Color.primary.opacity(0.08)
}
