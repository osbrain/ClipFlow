import AppKit
import ClipFlowCore
import ClipFlowSystem
import SwiftUI

public struct MainPanelView: View {
    @Bindable private var model: AppModel
    @Bindable private var settings: SettingsModel
    private let browserModel: BrowserTabModel?
    private let inputState: PanelInputStateStore
    private let showSettings: () -> Void

    @FocusState private var focusTarget: PanelFocusTarget?
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var showingDeleteConfirmation = false
    @State private var showingCreateCategory = false
    @State private var categoryName = ""
    @State private var historyReloadTask: Task<Void, Never>?

    public init(
        model: AppModel,
        settings: SettingsModel,
        browserModel: BrowserTabModel? = nil,
        inputState: PanelInputStateStore = PanelInputStateStore(),
        showSettings: @escaping () -> Void = {}
    ) {
        self.model = model
        self.settings = settings
        self.browserModel = browserModel
        self.inputState = inputState
        self.showSettings = showSettings
    }

    public var body: some View {
        VStack(spacing: 0) {
            ClipFlowHeader(
                browserTab: browserModel?.isShowing == true ? browserModel?.selectedTab : nil,
                pasteDestinationName: model.pasteDestinationName,
                showSettings: {
                    focusTarget = nil
                    showSettings()
                }
            )

            Divider()

            HStack(spacing: 0) {
                leftPane
                    .frame(minWidth: 400, idealWidth: 480, maxWidth: .infinity)

                Divider()

                rightPane
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
                    .simultaneousGesture(TapGesture().onEnded {
                        focusTarget = nil
                    })
            }
        }
        .frame(
            minWidth: MainPanelLayout.minimumWidth,
            idealWidth: MainPanelLayout.idealWidth,
            maxWidth: MainPanelLayout.maximumWidth,
            minHeight: MainPanelLayout.minimumHeight
        )
        .background(.regularMaterial)
        .clipShape(
            RoundedRectangle(
                cornerRadius: ClipFlowVisualStyle.windowRadius,
                style: .continuous
            )
        )
        .overlay(alignment: .bottom) {
            if let errorMessage = activeErrorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red.opacity(0.65))
                    }
                    .padding(12)
            }
        }
        .task {
            focusTarget = .search
            synchronizeInputSearchState()
            await model.reload()
            if browserModel?.isShowing == true {
                await browserModel?.refresh()
            }
        }
        .onChange(of: focusTarget) { synchronizeFocusState() }
        .onChange(of: inputState.requestedListFocus) { _, request in
            applyListFocusRequest(request)
        }
        .onChange(of: model.items.map(\.id)) { repairListFocus() }
        .onChange(of: browserTabIDs) { repairListFocus() }
        .onChange(of: showingRename) { synchronizeSheetState() }
        .onChange(of: showingDeleteConfirmation) { synchronizeSheetState() }
        .onChange(of: showingCreateCategory) { synchronizeSheetState() }
        .onChange(of: browserModel?.isShowing) { handleHistoryModeChange() }
        .alert(L10n.string("action.rename"), isPresented: $showingRename) {
            TextField(L10n.string("rename.title.placeholder"), text: $renameText)
            Button(L10n.string("common.cancel"), role: .cancel) {}
            Button(L10n.string("common.save")) {
                Task { await model.renameSelection(to: renameText) }
            }
        }
        .alert(L10n.string("action.delete"), isPresented: $showingDeleteConfirmation) {
            Button(L10n.string("common.cancel"), role: .cancel) {}
            Button(L10n.string("action.delete"), role: .destructive) {
                Task { await model.deleteSelection() }
            }
        } message: {
            Text(L10n.string("delete.confirmation.message"))
        }
        .alert(L10n.string("category.new"), isPresented: $showingCreateCategory) {
            TextField(L10n.string("category.name.placeholder"), text: $categoryName)
            Button(L10n.string("common.cancel"), role: .cancel) {}
            Button(L10n.string("common.create")) {
                Task { await model.createCategory(named: categoryName) }
            }
        }
    }

    private var leftPane: some View {
        VStack(spacing: 0) {
            HistorySearchField(
                text: searchBinding,
                resultCount: activeResultCount,
                isLoading: browserModel?.isShowing == true ? false : model.isLoading,
                focusTarget: $focusTarget
            )
            .padding(.horizontal, ClipFlowVisualStyle.panelPadding)
            .padding(.top, 10)

            HistoryFilterStrip(
                selectedFilter: selectedFilter,
                categories: model.categories,
                includesBrowserTabs: browserModel != nil,
                selectFilter: selectFilter,
                createCategory: beginCreateCategory,
                deleteCategory: { categoryID in
                    Task { await model.deleteCategory(categoryID) }
                }
            )

            if let browserModel, browserModel.isShowing {
                BrowserTabListView(
                    model: browserModel,
                    focusTarget: $focusTarget
                )
            } else {
                HistoryCardList(
                    model: model,
                    rowHeight: settings.listDensity.rowHeight,
                    focusTarget: $focusTarget,
                    beginRename: beginRename,
                    beginDelete: beginDelete
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.2))
    }

    @ViewBuilder
    private var rightPane: some View {
        if let browserModel, browserModel.isShowing {
            BrowserTabDetailView(model: browserModel)
        } else {
            DetailView(
                item: model.selectedItem,
                visual: model.selectedItemID.flatMap { model.visuals[$0] },
                settings: settings,
                contextActions: model.availableContextActions,
                performContextAction: { action in
                    Task { await model.performContextAction(action) }
                },
                favorite: { Task { await model.toggleFavoriteSelection() } },
                rename: beginRename,
                delete: beginDelete,
                applicationActions: model.availableApplicationActions,
                performApplicationAction: { action in
                    Task { await model.performApplicationAction(action) }
                }
            )
            .task(id: model.selectedItem?.contentHash) {
                guard let item = model.selectedItem,
                      item.kind == .image || item.kind == .file || item.kind == .mixed else {
                    return
                }
                model.requestThumbnail(for: item, maximumPixelSize: 720)
            }
        }
    }

    private var activeErrorMessage: String? {
        browserModel?.isShowing == true ? browserModel?.errorMessage : model.errorMessage
    }

    private var activeResultCount: Int {
        browserModel?.isShowing == true ? browserModel?.filteredTabs.count ?? 0 : model.items.count
    }

    private var browserTabIDs: [String] {
        browserModel?.filteredTabs.map(\.id) ?? []
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: {
                if let browserModel, browserModel.isShowing {
                    return browserModel.searchText
                }
                return model.searchText
            },
            set: { newValue in
                inputState.searchText = newValue
                if let browserModel, browserModel.isShowing {
                    browserModel.searchText = newValue
                    if browserModel.selectedTab == nil {
                        browserModel.selectedTabID = browserModel.filteredTabs.first?.id
                    }
                } else {
                    model.searchText = newValue
                    scheduleHistoryReload()
                }
            }
        )
    }

    private var selectedFilter: HistoryFilter {
        if browserModel?.isShowing == true { return .browserTabs }
        if model.favoritesOnly { return .favorites }
        if let categoryID = model.selectedCategoryID { return .category(categoryID) }
        if let kind = model.selectedKind { return .kind(kind) }
        return .all
    }

    private func selectFilter(_ filter: HistoryFilter) {
        focusTarget = nil
        if filter == .browserTabs, let browserModel {
            model.apply(.browserTabs)
            browserModel.isShowing = true
            browserModel.searchText = ""
            inputState.searchText = ""
            Task { await browserModel.refresh() }
            return
        }

        browserModel?.isShowing = false
        model.apply(filter)
        inputState.searchText = model.searchText
        Task { await model.reload() }
    }

    private func scheduleHistoryReload() {
        historyReloadTask?.cancel()
        historyReloadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await model.reload()
        }
    }

    private func synchronizeInputSearchState() {
        inputState.searchText = browserModel?.isShowing == true
            ? browserModel?.searchText ?? ""
            : model.searchText
    }

    private func synchronizeSheetState() {
        inputState.isPresentingSheet = showingRename || showingDeleteConfirmation || showingCreateCategory
        if inputState.isPresentingSheet {
            inputState.focus = .editing
        } else {
            synchronizeFocusState()
        }
    }

    private func beginRename() {
        renameText = model.selectedItem?.customTitle
            ?? model.selectedItem?.previewText
            ?? ""
        showingRename = true
    }

    private func beginDelete() {
        showingDeleteConfirmation = true
    }

    private func beginCreateCategory() {
        categoryName = ""
        showingCreateCategory = true
    }

    private func synchronizeFocusState() {
        guard !inputState.isPresentingSheet else { return }
        switch focusTarget {
        case .search:
            inputState.focus = .search
        case let .history(id):
            guard browserModel?.isShowing != true,
                  model.items.contains(where: { $0.id == id }) else {
                focusTarget = nil
                inputState.focus = .details
                return
            }
            model.selectedItemID = id
            inputState.focus = .list
        case let .browser(id):
            guard browserModel?.isShowing == true,
                  browserTabIDs.contains(id) else {
                focusTarget = nil
                inputState.focus = .details
                return
            }
            browserModel?.selectedTabID = id
            inputState.focus = .list
        case nil:
            inputState.focus = .details
        }
    }

    private func applyListFocusRequest(_ request: PanelListFocusRequest?) {
        guard let request else { return }
        defer { inputState.clearListFocusRequest() }

        switch request {
        case let .history(id):
            guard browserModel?.isShowing != true,
                  model.items.contains(where: { $0.id == id }) else {
                repairListFocus()
                return
            }
            model.selectedItemID = id
            focusTarget = .history(id)
        case let .browser(id):
            guard browserModel?.isShowing == true,
                  browserTabIDs.contains(id) else {
                repairListFocus()
                return
            }
            browserModel?.selectedTabID = id
            focusTarget = .browser(id)
        }
    }

    private func repairListFocus() {
        switch focusTarget {
        case let .history(id):
            guard browserModel?.isShowing != true else {
                focusTarget = nil
                return
            }
            guard model.items.contains(where: { $0.id == id }) else {
                if let selectedItemID = model.selectedItemID,
                   model.items.contains(where: { $0.id == selectedItemID }) {
                    focusTarget = .history(selectedItemID)
                } else {
                    focusTarget = nil
                }
                return
            }
        case let .browser(id):
            guard browserModel?.isShowing == true else {
                focusTarget = nil
                return
            }
            guard browserTabIDs.contains(id) else {
                if let selectedTabID = browserModel?.selectedTabID,
                   browserTabIDs.contains(selectedTabID) {
                    focusTarget = .browser(selectedTabID)
                } else {
                    focusTarget = nil
                }
                return
            }
        case .search, nil:
            return
        }
    }

    private func handleHistoryModeChange() {
        synchronizeInputSearchState()
        inputState.clearListFocusRequest()
        repairListFocus()
    }
}

private struct ClipFlowHeader: View {
    let browserTab: ClipFlowSystem.BrowserTab?
    let pasteDestinationName: String?
    let showSettings: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            brandIcon
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("app.name"))
                    .font(.title3.weight(.bold))
                Text(L10n.string("app.privacy.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 18)

            if let browserTab {
                HeaderSourceContext(
                    icon: browserApplicationIcon(for: browserTab.browser),
                    fallbackSymbol: browserTab.browser.symbolName,
                    title: browserTab.browser.displayName,
                    subtitle: browserTab.title
                )
            } else {
                HeaderSourceContext(
                    icon: nil,
                    fallbackSymbol: pasteDestinationName == nil
                        ? "clipboard"
                        : "arrow.right.circle.fill",
                    title: pasteDestinationName
                        ?? L10n.string("header.clipboardTarget"),
                    subtitle: L10n.string("header.pasteTarget")
                )
            }

            Button(action: showSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(
                        width: HeaderControlLayout.height,
                        height: HeaderControlLayout.height
                    )
            }
            .buttonStyle(HeaderToolButtonStyle())
            .accessibilityLabel(L10n.string("settings.title"))
            .help(L10n.string("settings.title"))
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var brandIcon: some View {
        if let icon = ClipFlowBrandIcon.image() {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(.thinMaterial)
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.accentColor.opacity(0.45))
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
    }

    private func browserApplicationIcon(for browser: BrowserKind) -> NSImage? {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: browser.bundleID
        ) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: applicationURL.path)
    }
}

private struct HeaderSourceContext: View {
    let icon: NSImage?
    let fallbackSymbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 9) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: fallbackSymbol).foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: HeaderControlLayout.height)
        .background(
            Color.primary.opacity(HeaderControlLayout.fillOpacity),
            in: RoundedRectangle(cornerRadius: HeaderControlLayout.cornerRadius)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct HeaderToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(
                Color.primary.opacity(
                    configuration.isPressed
                        ? HeaderControlLayout.fillOpacity * 1.8
                        : HeaderControlLayout.fillOpacity
                ),
                in: RoundedRectangle(cornerRadius: HeaderControlLayout.cornerRadius)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: HeaderControlLayout.cornerRadius)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct HistorySearchField: View {
    @Binding var text: String
    let resultCount: Int
    let isLoading: Bool
    @FocusState.Binding var focusTarget: PanelFocusTarget?

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(L10n.string("history.search.placeholder"), text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($focusTarget, equals: .search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("action.clearSearch"))
                .help(L10n.string("action.clearSearch"))
            }

            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Text(resultCount, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: ClipFlowVisualStyle.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ClipFlowVisualStyle.controlRadius)
                .stroke(focusTarget == .search ? Color.accentColor.opacity(0.75) : ClipFlowVisualStyle.hairlineColor)
        }
    }
}

private struct HistoryFilterStrip: View {
    let selectedFilter: HistoryFilter
    let categories: [ClipCategory]
    let includesBrowserTabs: Bool
    let selectFilter: (HistoryFilter) -> Void
    let createCategory: () -> Void
    let deleteCategory: (UUID) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullStrip
                .fixedSize(horizontal: true, vertical: false)
            compactStrip
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ClipFlowVisualStyle.panelPadding)
        .padding(.vertical, 10)
    }

    private var fullStrip: some View {
        HStack(spacing: 7) {
            chip(.all, title: L10n.string("filter.all"), icon: "tray.full")
            chip(.favorites, title: L10n.string("filter.favorites"), icon: "star")
            chip(.kind(.text), title: L10n.string("filter.text"), icon: ClipboardKind.text.presentation.symbolName)
            chip(.kind(.richText), title: L10n.string("filter.richText"), icon: ClipboardKind.richText.presentation.symbolName)
            chip(.kind(.image), title: L10n.string("filter.images"), icon: ClipboardKind.image.presentation.symbolName)
            chip(.kind(.file), title: L10n.string("filter.files"), icon: ClipboardKind.file.presentation.symbolName)
            chip(.kind(.link), title: L10n.string("filter.links"), icon: ClipboardKind.link.presentation.symbolName)
            if includesBrowserTabs {
                chip(.browserTabs, title: L10n.string("filter.browserTabs"), icon: "macwindow.on.rectangle")
            }
            categoryChips
            createCategoryButton
        }
    }

    private var compactStrip: some View {
        HStack(spacing: 7) {
            chip(.all, title: L10n.string("filter.all"), icon: "tray.full")
            chip(.favorites, title: L10n.string("filter.favorites"), icon: "star")

            Menu {
                overflowMenu
            } label: {
                FilterMenuChip(
                    title: L10n.string("filter.more"),
                    icon: "ellipsis.circle",
                    isSelected: !HistoryFilterStripLayout.isPrimary(selectedFilter)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L10n.string("filter.more"))
        }
    }

    @ViewBuilder
    private var categoryChips: some View {
        ForEach(categories) { category in
            FilterChip(
                title: category.name,
                icon: "folder",
                isSelected: selectedFilter == .category(category.id)
            ) {
                selectFilter(.category(category.id))
            }
            .contextMenu {
                Button(L10n.string("category.delete"), role: .destructive) {
                    deleteCategory(category.id)
                }
            }
        }
    }

    @ViewBuilder
    private var overflowMenu: some View {
        overflowButton(
            .kind(.text),
            title: L10n.string("filter.text"),
            icon: ClipboardKind.text.presentation.symbolName
        )
        overflowButton(
            .kind(.richText),
            title: L10n.string("filter.richText"),
            icon: ClipboardKind.richText.presentation.symbolName
        )
        overflowButton(
            .kind(.image),
            title: L10n.string("filter.images"),
            icon: ClipboardKind.image.presentation.symbolName
        )
        overflowButton(
            .kind(.file),
            title: L10n.string("filter.files"),
            icon: ClipboardKind.file.presentation.symbolName
        )
        overflowButton(
            .kind(.link),
            title: L10n.string("filter.links"),
            icon: ClipboardKind.link.presentation.symbolName
        )
        if includesBrowserTabs {
            overflowButton(
                .browserTabs,
                title: L10n.string("filter.browserTabs"),
                icon: "macwindow.on.rectangle"
            )
        }
        if !categories.isEmpty {
            Divider()
            ForEach(categories) { category in
                overflowButton(
                    .category(category.id),
                    title: category.name,
                    icon: "folder"
                )
            }
            Menu(L10n.string("category.delete"), systemImage: "trash") {
                ForEach(categories) { category in
                    Button(category.name, role: .destructive) {
                        deleteCategory(category.id)
                    }
                }
            }
        }
        Divider()
        Button(action: createCategory) {
            Label(L10n.string("category.new"), systemImage: "plus")
        }
    }

    private var createCategoryButton: some View {
        Button(action: createCategory) {
            Image(systemName: "plus")
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(L10n.string("category.new"))
        .help(L10n.string("category.new"))
    }

    private func overflowButton(
        _ filter: HistoryFilter,
        title: String,
        icon: String
    ) -> some View {
        Button {
            selectFilter(filter)
        } label: {
            HStack(spacing: 7) {
                Label(title, systemImage: icon)
                Spacer(minLength: 12)
                if selectedFilter == filter {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func chip(_ filter: HistoryFilter, title: String, icon: String) -> some View {
        FilterChip(title: title, icon: icon, isSelected: selectedFilter == filter) {
            selectFilter(filter)
        }
    }
}

private struct FilterMenuChip: View {
    let title: String
    let icon: String
    let isSelected: Bool

    var body: some View {
        Label(title, systemImage: icon)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.primary)
            .background(
                isSelected ? Color.accentColor.opacity(ClipFlowVisualStyle.selectedFillOpacity) : .clear,
                in: RoundedRectangle(cornerRadius: ClipFlowVisualStyle.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ClipFlowVisualStyle.controlRadius)
                    .stroke(
                        isSelected
                            ? Color.accentColor.opacity(ClipFlowVisualStyle.selectedBorderOpacity)
                            : ClipFlowVisualStyle.hairlineColor
                    )
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct HistoryCardList: View {
    @Bindable var model: AppModel
    let rowHeight: CGFloat
    @FocusState.Binding var focusTarget: PanelFocusTarget?
    let beginRename: () -> Void
    let beginDelete: () -> Void

    var body: some View {
        Group {
            if model.items.isEmpty && !model.isLoading {
                ContentUnavailableView(
                    L10n.string("history.empty.title"),
                    systemImage: "doc.on.clipboard",
                    description: Text(
                        model.searchText.isEmpty
                            ? L10n.string("history.empty.description")
                            : L10n.string("history.empty.searchDescription")
                    )
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(model.items) { item in
                                Button {
                                    select(item)
                                } label: {
                                    HistoryCardRow(
                                        item: item,
                                        visual: model.visuals[item.id],
                                        isSelected: model.selectedItemID == item.id,
                                        rowHeight: rowHeight
                                    )
                                    .accessibilityElement(children: .combine)
                                }
                                .buttonStyle(.plain)
                                .id(item.id)
                                .focused($focusTarget, equals: .history(item.id))
                                .simultaneousGesture(TapGesture(count: 2).onEnded {
                                    select(item)
                                    Task { await model.pasteSelection() }
                                })
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAddTraits(
                                    model.selectedItemID == item.id ? .isSelected : []
                                )
                                .accessibilityAction { select(item) }
                                .task(id: item.contentHash) {
                                    if item.kind == .image || item.kind == .file || item.kind == .mixed {
                                        model.requestThumbnail(for: item, maximumPixelSize: 320)
                                    }
                                }
                                .onDrag {
                                    model.dragProvider(for: item)
                                        ?? NSItemProvider(object: item.previewText as NSString)
                                }
                                .contextMenu {
                                    itemContextMenu(item)
                                }
                            }
                        }
                        .padding(.horizontal, ClipFlowVisualStyle.panelPadding)
                        .padding(.bottom, ClipFlowVisualStyle.panelPadding)
                    }
                    .clipFlowScrollAppearance()
                    .onChange(of: model.selectedItemID) { _, selectedItemID in
                        guard let selectedItemID else { return }
                        withAnimation(.easeOut(duration: 0.16)) {
                            proxy.scrollTo(selectedItemID)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func select(_ item: ClipboardItem) {
        model.selectedItemID = item.id
        focusTarget = .history(item.id)
    }

    @ViewBuilder
    private func itemContextMenu(_ item: ClipboardItem) -> some View {
        Button(L10n.string("detail.paste")) {
            select(item)
            Task { await model.pasteSelection() }
        }
        Button(L10n.string("detail.preview")) {
            select(item)
            model.previewSelection()
        }
        ForEach(model.applicationActions(for: item), id: \.self) { action in
            Button(action.localizedDisplayName) {
                select(item)
                Task { await model.performApplicationAction(action) }
            }
        }
        Button(L10n.string(item.isFavorite ? "action.removeFavorite" : "action.favorite")) {
            select(item)
            Task { await model.toggleFavoriteSelection() }
        }
        Button(L10n.string("action.rename")) {
            select(item)
            beginRename()
        }
        if !model.categories.isEmpty {
            Menu(L10n.string("category.assign")) {
                ForEach(model.categories) { category in
                    Button(category.name) {
                        select(item)
                        Task { await model.assignSelection(to: category.id) }
                    }
                }
            }
        }
        Divider()
        Button(L10n.string("action.delete"), role: .destructive) {
            select(item)
            beginDelete()
        }
    }
}

private struct HistoryCardRow: View {
    let item: ClipboardItem
    let visual: ClipboardVisualDescriptor?
    let isSelected: Bool
    let rowHeight: CGFloat
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.displayTitle)
                        .font(.body.weight(.semibold))
                        .lineLimit(rowHeight >= 70 ? 2 : 1)
                    Spacer(minLength: 4)
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel(L10n.string("filter.favorites"))
                    }
                }

                HStack(spacing: 7) {
                    SourceApplicationLabel(name: item.appName, icon: visual?.applicationIcon)
                    Text("·").foregroundStyle(.tertiary)
                    Label(item.kind.localizedDisplayName, systemImage: item.kind.presentation.symbolName)
                    Text("·").foregroundStyle(.tertiary)
                    Text(HistoryTimePresentation.text(for: item.updatedAt))
                    Text("·").foregroundStyle(.tertiary)
                    Text(L10n.formattedByteCount(item.byteSize))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: rowHeight)
        .background {
            RoundedRectangle(cornerRadius: ClipFlowVisualStyle.cardRadius)
                .fill(
                    isSelected
                        ? ClipFlowVisualStyle.selectedRowFillColor
                        : Color.primary.opacity(isHovering ? 0.07 : 0.035)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: ClipFlowVisualStyle.cardRadius)
                .stroke(
                    isSelected
                        ? Color.accentColor.opacity(ClipFlowVisualStyle.selectedBorderOpacity)
                        : ClipFlowVisualStyle.hairlineColor,
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .shadow(color: .black.opacity(isSelected ? 0.08 : 0), radius: 8, y: 3)
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        let size: CGFloat = rowHeight >= 70 ? 54 : 44
        if let image = visual?.thumbnail {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10).stroke(ClipFlowVisualStyle.hairlineColor)
                }
        } else {
            ClipboardKindBadge(kind: item.kind, size: size)
        }
    }
}
