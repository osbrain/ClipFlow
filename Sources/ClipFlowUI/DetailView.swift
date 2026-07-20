import AppKit
import ClipFlowCore
import ClipFlowSystem
import SwiftUI

struct DetailView: View {
    let item: ClipboardItem?
    let visual: ClipboardVisualDescriptor?
    let settings: SettingsModel
    let contextActions: [ItemContextAction]
    let performContextAction: (ItemContextAction) -> Void
    let favorite: () -> Void
    let rename: () -> Void
    let delete: () -> Void
    let applicationActions: [ApplicationAction]
    let performApplicationAction: (ApplicationAction) -> Void

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: ClipFlowVisualStyle.sectionSpacing) {
                        SelectedSourceHeader(item: item, visual: visual)
                        PreviewCard(
                            item: item,
                            visual: visual,
                            showFullPreview: contextActions.contains(.quickLook)
                                ? { performContextAction(.quickLook) }
                                : nil
                        )
                        DetailActionStack(
                            item: item,
                            contextActions: contextActions,
                            performContextAction: performContextAction,
                            favorite: favorite,
                            rename: rename,
                            delete: delete,
                            applicationActions: applicationActions,
                            performApplicationAction: performApplicationAction
                        )
                        metadataGrid(for: item)
                    }
                    .padding(ClipFlowVisualStyle.panelPadding)
                }
                .clipFlowScrollAppearance()
            } else {
                ClipFlowEmptyStateView(
                    title: L10n.string("detail.empty.title"),
                    description: L10n.string("detail.empty.description"),
                    symbol: "cursorarrow.click"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.32))
    }

    private var fieldVisibility: DetailFieldVisibility {
        DetailFieldVisibility(
            showsSource: settings.showDetailSource,
            showsKind: settings.showDetailType,
            showsCreated: settings.showDetailCreatedAt,
            showsLastUsed: settings.showDetailLastUsedAt,
            showsSize: settings.showDetailSize,
            showsFormatting: settings.showDetailFormatting
        )
    }

    @ViewBuilder
    private func metadataGrid(for item: ClipboardItem) -> some View {
        let fields = fieldVisibility.visibleFields
        if !fields.isEmpty {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(fields, id: \.self) { field in
                    let presentation = metadataPresentation(field, item: item)
                    MetadataCard(
                        icon: presentation.icon,
                        title: presentation.title,
                        value: presentation.value
                    )
                }
            }
        }
    }

    private func metadataPresentation(
        _ field: DetailField,
        item: ClipboardItem
    ) -> (icon: String, title: String, value: String) {
        switch field {
        case .source:
            ("app", L10n.string("detail.source"), item.appName)
        case .kind:
            (item.kind.presentation.symbolName, L10n.string("detail.kind"), item.kind.localizedDisplayName)
        case .created:
            ("calendar", L10n.string("detail.created"), L10n.formattedDateTime(item.createdAt))
        case .lastUsed:
            ("clock.arrow.circlepath", L10n.string("detail.lastUsed"), item.lastUsedAt.map(L10n.formattedDateTime) ?? "—")
        case .size:
            ("externaldrive", L10n.string("detail.size"), L10n.formattedByteCount(item.byteSize))
        case .formatting:
            ("textformat", L10n.string("detail.formatting"), item.kind.localizedFormattingAvailability)
        }
    }
}

private struct SelectedSourceHeader: View {
    let item: ClipboardItem
    let visual: ClipboardVisualDescriptor?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = visual?.applicationIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app.dashed")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                Text(item.appName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ClipboardKindBadge(kind: item.kind, size: 34)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PreviewCard: View {
    let item: ClipboardItem
    let visual: ClipboardVisualDescriptor?
    let showFullPreview: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label(L10n.string("detail.preview"), systemImage: "eye")
                    .font(.headline)
                Spacer(minLength: 8)
                if let showFullPreview {
                    Button(action: showFullPreview) {
                        Label(
                            L10n.string("detail.fullPreview"),
                            systemImage: "arrow.up.left.and.arrow.down.right"
                        )
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help(L10n.string("detail.fullPreview"))
                }
            }

            preview
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(ClipFlowVisualStyle.hairlineColor)
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind.detailPreviewMode {
        case .image:
            if let thumbnail = visual?.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 120,
                        maxHeight: DetailPreviewLayout.imageMaximumHeight
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel(item.displayTitle)
            } else {
                fallback(symbol: "photo", text: item.previewText, lineLimit: 5)
            }
        case .file:
            HStack(alignment: .top, spacing: 12) {
                if let thumbnail = visual?.thumbnail {
                    adjacentThumbnail(thumbnail, size: 56)
                } else {
                    ClipboardKindBadge(kind: .file, size: 46)
                        .accessibilityHidden(true)
                }
                Text(normalizedFilePath)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(DetailPreviewLayout.lineLimit(for: .file))
                    .truncationMode(.tail)
            }
        case .link:
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(item.previewText)
                    .foregroundStyle(.tint)
                    .textSelection(.enabled)
                    .lineLimit(DetailPreviewLayout.lineLimit(for: .link))
                    .truncationMode(.middle)
            }
        case .text:
            Text(item.previewText)
                .textSelection(.enabled)
                .lineLimit(DetailPreviewLayout.lineLimit(for: .text))
                .truncationMode(.tail)
        case .mixed:
            HStack(alignment: .top, spacing: 12) {
                if let thumbnail = visual?.thumbnail {
                    adjacentThumbnail(thumbnail, size: 56)
                } else {
                    ClipboardKindBadge(kind: .mixed, size: 46)
                        .accessibilityHidden(true)
                }
                Text(item.previewText)
                    .textSelection(.enabled)
                    .lineLimit(DetailPreviewLayout.lineLimit(for: .mixed))
                    .truncationMode(.tail)
            }
        case .unknown:
            fallback(
                symbol: "questionmark.square.dashed",
                text: item.previewText,
                lineLimit: DetailPreviewLayout.lineLimit(for: .unknown)
            )
        }
    }

    private var normalizedFilePath: String {
        let value = item.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), url.isFileURL {
            return url.standardizedFileURL.path(percentEncoded: false)
        }
        return NSString(string: value).standardizingPath
    }

    private func fallback(symbol: String, text: String, lineLimit: Int?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .textSelection(.enabled)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
        }
    }

    private func adjacentThumbnail(_ thumbnail: NSImage, size: CGFloat) -> some View {
        Image(nsImage: thumbnail)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(ClipFlowVisualStyle.hairlineColor)
            }
            .accessibilityHidden(true)
    }
}

private struct DetailActionStack: View {
    let item: ClipboardItem
    let contextActions: [ItemContextAction]
    let performContextAction: (ItemContextAction) -> Void
    let favorite: () -> Void
    let rename: () -> Void
    let delete: () -> Void
    let applicationActions: [ApplicationAction]
    let performApplicationAction: (ApplicationAction) -> Void

    var body: some View {
        VStack(spacing: 9) {
            let stackActions = DetailActionPresentation.stackActions(from: contextActions)

            if stackActions.contains(.pasteOriginal) {
                contextActionButton(.pasteOriginal)
            }

            let secondaryActions = stackActions.filter { $0 != .pasteOriginal }
            if !secondaryActions.isEmpty {
                LazyVGrid(
                    columns: secondaryActions.count == 1
                        ? [GridItem(.flexible())]
                        : [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                    spacing: 8
                ) {
                    ForEach(secondaryActions, id: \.self) { action in
                        contextActionButton(action)
                    }
                }
            }

            HStack(spacing: 8) {
                compactButton(
                    L10n.string(item.isFavorite ? "action.removeFavorite" : "action.favorite"),
                    icon: item.isFavorite ? "star.fill" : "star",
                    action: favorite
                )
                compactButton(L10n.string("action.rename"), icon: "pencil", action: rename)
                compactButton(
                    L10n.string("action.delete"),
                    icon: "trash",
                    role: .destructive,
                    action: delete
                )
            }

            ForEach(applicationActions, id: \.self) { applicationAction in
                actionButton(
                    applicationAction.localizedDisplayName,
                    icon: applicationAction.symbolName,
                    prominent: false
                ) {
                    performApplicationAction(applicationAction)
                }
            }
        }
    }

    @ViewBuilder
    private func contextActionButton(_ action: ItemContextAction) -> some View {
        let title = L10n.string(action.titleKey(for: item.kind))
        if action == .pasteOriginal {
            actionButton(title, icon: action.symbolName, prominent: true) {
                performContextAction(action)
            }
            .keyboardShortcut(.return, modifiers: [])
        } else if action == .pastePlainText || action == .pasteFilePath {
            actionButton(title, icon: action.symbolName, prominent: false) {
                performContextAction(action)
            }
            .keyboardShortcut(.return, modifiers: .command)
        } else {
            actionButton(title, icon: action.symbolName, prominent: false) {
                performContextAction(action)
            }
        }
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        icon: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionLabel(title: title, icon: icon)
        }
        .buttonStyle(
            DetailActionButtonStyle(
                kind: prominent ? .primary : .secondary
            )
        )
        .accessibilityLabel(title)
        .help(title)
    }

    private func actionLabel(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .accessibilityHidden(true)
            Text(title)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
    }

    private func compactButton(
        _ title: String,
        icon: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
        .buttonStyle(DetailActionButtonStyle(kind: .utility, role: role))
        .accessibilityLabel(title)
        .help(title)
    }
}

private enum DetailActionButtonKind {
    case primary
    case secondary
    case utility

    var height: CGFloat {
        switch self {
        case .primary: ClipFlowVisualStyle.primaryActionHeight
        case .secondary: ClipFlowVisualStyle.secondaryActionHeight
        case .utility: ClipFlowVisualStyle.utilityActionHeight
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .primary: 12
        case .secondary: 10
        case .utility: 8
        }
    }
}

private struct DetailActionButtonStyle: ButtonStyle {
    let kind: DetailActionButtonKind
    var role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(kind == .utility ? .callout : .callout.weight(.medium))
            .foregroundStyle(foregroundStyle)
            .frame(maxWidth: .infinity)
            .frame(height: kind.height)
            .background {
                RoundedRectangle(cornerRadius: kind.cornerRadius, style: .continuous)
                    .fill(backgroundStyle)
            }
            .overlay {
                RoundedRectangle(cornerRadius: kind.cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: kind == .primary ? 0 : 1)
            }
            .contentShape(
                RoundedRectangle(cornerRadius: kind.cornerRadius, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundStyle: Color {
        if kind == .primary { return .white }
        if role == .destructive { return .red }
        return .primary
    }

    private var backgroundStyle: AnyShapeStyle {
        switch kind {
        case .primary:
            AnyShapeStyle(Color.accentColor)
        case .secondary:
            AnyShapeStyle(.thinMaterial)
        case .utility:
            AnyShapeStyle(Color.primary.opacity(0.085))
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            .clear
        case .secondary:
            ClipFlowVisualStyle.hairlineColor.opacity(0.75)
        case .utility:
            ClipFlowVisualStyle.hairlineColor.opacity(0.5)
        }
    }
}
