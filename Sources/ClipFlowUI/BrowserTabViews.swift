import AppKit
import ClipFlowSystem
import SwiftUI

struct BrowserTabListView: View {
    @Bindable var model: BrowserTabModel
    @FocusState.Binding var focusTarget: PanelFocusTarget?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(L10n.string("filter.browserTabs"), systemImage: "macwindow.on.rectangle")
                    .font(.headline)
                Spacer()
                Button {
                    focusTarget = nil
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(L10n.string("browser.refresh"))
                .help(L10n.string("browser.refresh"))
            }
            .padding(.horizontal, ClipFlowVisualStyle.panelPadding)
            .padding(.bottom, 8)

            if model.filteredTabs.isEmpty {
                BrowserTabEmptyState(model: model)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(model.filteredTabs) { tab in
                                Button {
                                    select(tab)
                                } label: {
                                    BrowserTabCard(
                                        tab: tab,
                                        isSelected: model.selectedTabID == tab.id
                                    )
                                    .accessibilityElement(children: .combine)
                                }
                                .buttonStyle(.plain)
                                .id(tab.id)
                                .focused($focusTarget, equals: .browser(tab.id))
                                .simultaneousGesture(TapGesture(count: 2).onEnded {
                                    select(tab)
                                    Task { await model.activateSelection() }
                                })
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAddTraits(
                                    model.selectedTabID == tab.id ? .isSelected : []
                                )
                                .accessibilityAction { select(tab) }
                            }
                        }
                        .padding(.horizontal, ClipFlowVisualStyle.panelPadding)
                        .padding(.bottom, ClipFlowVisualStyle.panelPadding)
                    }
                    .clipFlowScrollAppearance()
                    .onChange(of: model.selectedTabID) { _, selectedTabID in
                        guard let selectedTabID else { return }
                        withAnimation(.easeOut(duration: 0.16)) {
                            proxy.scrollTo(selectedTabID)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func select(_ tab: BrowserTab) {
        model.selectedTabID = tab.id
        focusTarget = .browser(tab.id)
    }
}

private struct BrowserTabCard: View {
    let tab: BrowserTab
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            BrowserSourceIcon(browser: tab.browser, size: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(tab.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(tab.browser.displayName)
                    Text("·")
                    Text(tab.url)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 66)
        .background {
            RoundedRectangle(cornerRadius: ClipFlowVisualStyle.cardRadius)
                .fill(isSelected ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.primary.opacity(isHovering ? 0.07 : 0.035)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: ClipFlowVisualStyle.cardRadius)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.9) : ClipFlowVisualStyle.hairlineColor,
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
    }
}

private struct BrowserTabEmptyState: View {
    @Bindable var model: BrowserTabModel

    var body: some View {
        if !model.searchText.isEmpty && !model.tabs.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        L10n.string("browser.empty.title"),
                        systemImage: "macwindow.on.rectangle",
                        description: Text(L10n.string("browser.empty.description"))
                    )
                    GlassSection(title: L10n.string("filter.browserTabs"), icon: "network") {
                        VStack(spacing: 8) {
                            ForEach(BrowserKind.allCases, id: \.self) { browser in
                                HStack(spacing: 10) {
                                    Image(systemName: browser.symbolName)
                                        .frame(width: 20)
                                        .accessibilityHidden(true)
                                    Text(browser.displayName)
                                    Spacer()
                                    Text(model.statuses[browser, default: .notRunning].displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(ClipFlowVisualStyle.panelPadding)
            }
            .clipFlowScrollAppearance()
        }
    }
}

struct BrowserTabDetailView: View {
    @Bindable var model: BrowserTabModel

    var body: some View {
        if let tab = model.selectedTab {
            ScrollView {
                VStack(alignment: .leading, spacing: ClipFlowVisualStyle.sectionSpacing) {
                    HStack(spacing: 12) {
                        BrowserSourceIcon(browser: tab.browser, size: 42)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tab.browser.displayName)
                                .font(.headline)
                            Text(L10n.string("filter.browserTabs"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    GlassSection(title: L10n.string("detail.preview"), icon: "macwindow") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(tab.title)
                                .font(.title3.weight(.semibold))
                                .textSelection(.enabled)
                            Text(tab.url)
                                .foregroundStyle(.tint)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await model.activateSelection() }
                    } label: {
                        Label(L10n.string("browser.open"), systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityLabel(L10n.string("browser.open"))

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(ClipFlowVisualStyle.panelPadding)
            }
            .clipFlowScrollAppearance()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.32))
        } else {
            ContentUnavailableView(
                L10n.string("browser.empty.selection.title"),
                systemImage: "cursorarrow.click",
                description: Text(L10n.string("browser.empty.selection.description"))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.32))
        }
    }
}

private struct BrowserSourceIcon: View {
    let browser: BrowserKind
    let size: CGFloat

    var body: some View {
        Group {
            if let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: browser.bundleID
            ) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path))
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: browser.symbolName)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: size, height: size)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: size * 0.26))
    }
}

extension BrowserKind {
    var symbolName: String {
        switch self {
        case .safari: "safari"
        case .chrome: "globe"
        case .edge: "globe.americas"
        }
    }
}

private extension BrowserAutomationStatus {
    var displayName: String {
        switch self {
        case .notInstalled: L10n.string("browser.status.notInstalled")
        case .notRunning: L10n.string("browser.status.notRunning")
        case .notAuthorized: L10n.string("browser.status.notAuthorized")
        case .authorized: L10n.string("browser.status.authorized")
        }
    }
}
