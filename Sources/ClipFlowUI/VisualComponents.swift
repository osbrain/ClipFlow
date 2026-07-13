import AppKit
import ClipFlowCore
import SwiftUI

public struct GlassSection<Content: View>: View {
    private let title: String
    private let icon: String
    private let content: Content

    public init(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ClipFlowVisualStyle.sectionSpacing) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.primary)
            content
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(ClipFlowVisualStyle.hairlineOpacity))
        }
    }
}

public struct GlassRow<Content: View>: View {
    private let icon: String
    private let title: String
    private let subtitle: String?
    private let content: Content

    public init(
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

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)
            content
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: ClipFlowVisualStyle.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ClipFlowVisualStyle.cardRadius)
                .stroke(Color.white.opacity(ClipFlowVisualStyle.hairlineOpacity))
        }
    }
}

public struct FilterChip: View {
    private let title: String
    private let icon: String
    private let isSelected: Bool
    private let action: () -> Void
    @State private var isHovering = false

    public init(
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

    public var body: some View {
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
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .help(title)
        .onHover { isHovering = $0 }
    }

    private var fillColor: Color {
        if isSelected {
            return Color.accentColor.opacity(ClipFlowVisualStyle.selectedFillOpacity)
        }
        return Color.white.opacity(isHovering ? 0.08 : 0)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(ClipFlowVisualStyle.selectedBorderOpacity)
        }
        return Color.white.opacity(ClipFlowVisualStyle.hairlineOpacity)
    }
}

public struct ClipboardKindBadge: View {
    private let kind: ClipboardKind
    private let size: CGFloat

    public init(kind: ClipboardKind, size: CGFloat = 36) {
        self.kind = kind
        self.size = size
    }

    public var body: some View {
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
            .accessibilityLabel(kind.rawValue)
    }
}

public struct SourceApplicationLabel: View {
    private let name: String
    private let icon: NSImage?

    public init(name: String, icon: NSImage?) {
        self.name = name
        self.icon = icon
    }

    public var body: some View {
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

public struct MetadataCard: View {
    private let icon: String
    private let title: String
    private let value: String

    public init(icon: String, title: String, value: String) {
        self.icon = icon
        self.title = title
        self.value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: ClipFlowVisualStyle.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ClipFlowVisualStyle.cardRadius)
                .stroke(Color.white.opacity(ClipFlowVisualStyle.hairlineOpacity))
        }
    }
}
