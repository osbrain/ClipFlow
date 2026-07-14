import SwiftUI

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
