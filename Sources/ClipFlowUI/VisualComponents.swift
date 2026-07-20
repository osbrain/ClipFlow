import AppKit
import ClipFlowCore
import SwiftUI

struct ClipFlowAuroraBackground: View {
    let materialOpacity: Double

    init(materialOpacity: Double = 1) {
        self.materialOpacity = materialOpacity
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .opacity(materialOpacity)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.16 * materialOpacity),
                    Color.purple.opacity(0.08 * materialOpacity),
                    Color.cyan.opacity(0.09 * materialOpacity)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.softLight)

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.26 * materialOpacity),
                    .clear
                ],
                center: .topLeading,
                startRadius: 18,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    Color.cyan.opacity(0.18 * materialOpacity),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 360
            )

            RadialGradient(
                colors: [
                    Color.purple.opacity(0.12 * materialOpacity),
                    .clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 520
            )
        }
        .allowsHitTesting(false)
    }
}

private struct ClipFlowGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let shadow: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.04),
                                Color.accentColor.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.36),
                                ClipFlowVisualStyle.hairlineColor.opacity(0.78),
                                Color.accentColor.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: .black.opacity(shadow ? 0.08 : 0),
                radius: shadow ? 16 : 0,
                x: 0,
                y: shadow ? 8 : 0
            )
    }
}

extension View {
    func clipFlowGlassSurface(
        cornerRadius: CGFloat = ClipFlowVisualStyle.cardRadius,
        shadow: Bool = true
    ) -> some View {
        modifier(
            ClipFlowGlassSurface(
                cornerRadius: cornerRadius,
                shadow: shadow
            )
        )
    }
}

struct ClipFlowMiniEmptyStateIllustration: View {
    private let symbol: String

    init(symbol: String = "sparkles") {
        self.symbol = symbol
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 34, height: 34)
                .offset(x: -4, y: -3)

            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 28, height: 28)
                .offset(x: 7, y: 6)

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.thinMaterial)
                .frame(width: 34, height: 28)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.34))
                }

            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
        }
        .frame(width: 44, height: 38)
        .accessibilityHidden(true)
    }
}

struct ClipFlowEmptyStateView: View {
    let title: String
    let description: String
    let symbol: String

    var body: some View {
        VStack(spacing: 12) {
            ClipFlowMiniEmptyStateIllustration(symbol: symbol)
                .scaleEffect(1.28)

            VStack(spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipFlowGlassSurface(cornerRadius: 18)
        .padding(ClipFlowVisualStyle.panelPadding)
    }
}

struct GlassSection<Content: View>: View {
    private let title: String
    private let icon: String
    private let content: Content

    init(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ClipFlowVisualStyle.sectionSpacing) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.primary)
            content
        }
        .padding(16)
        .clipFlowGlassSurface(cornerRadius: 14)
    }
}

struct GlassRow<Content: View>: View {
    private let icon: String
    private let title: String
    private let subtitle: String?
    private let content: Content

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 24)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .layoutPriority(1)

                    Spacer(minLength: 12)
                    content
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .clipFlowGlassSurface(shadow: false)
    }
}

struct FilterChip: View {
    private let title: String
    private let icon: String
    private let isSelected: Bool
    private let action: () -> Void
    @State private var isHovering = false

    init(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(fillColor, in: RoundedRectangle(cornerRadius: ClipFlowVisualStyle.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: ClipFlowVisualStyle.controlRadius)
                        .stroke(borderColor)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(title)
        .onHover { isHovering = $0 }
    }

    private var fillColor: Color {
        if isSelected {
            return Color.accentColor.opacity(ClipFlowVisualStyle.selectedFillOpacity)
        }
        return isHovering ? ClipFlowVisualStyle.hoverFillColor : .clear
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(ClipFlowVisualStyle.selectedBorderOpacity)
        }
        return ClipFlowVisualStyle.hairlineColor
    }
}

struct ClipboardKindBadge: View {
    private let kind: ClipboardKind
    private let size: CGFloat

    init(kind: ClipboardKind, size: CGFloat = 36) {
        self.kind = kind
        self.size = size
    }

    var body: some View {
        let presentation = kind.presentation

        Image(systemName: presentation.symbolName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(presentation.accent.color)
            .frame(width: size, height: size)
            .background(
                presentation.accent.color.opacity(0.16),
                in: RoundedRectangle(cornerRadius: size * 0.28)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(kind.localizedDisplayName)
            .help(kind.localizedDisplayName)
    }
}

struct SourceApplicationLabel: View {
    private let name: String
    private let icon: NSImage?

    init(name: String, icon: NSImage?) {
        self.name = name
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app.dashed")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)

            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}

struct MetadataCard: View {
    private let icon: String
    private let title: String
    private let value: String

    init(icon: String, title: String, value: String) {
        self.icon = icon
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(height: 18, alignment: .leading)
                .accessibilityHidden(true)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .clipFlowGlassSurface(shadow: false)
    }
}
