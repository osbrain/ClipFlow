import ClipFlowCore
import SwiftUI

public struct MainPanelView: View {
    @Bindable private var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var showingDeleteConfirmation = false

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                CategorySidebar(model: model)
                    .frame(width: 176)
                Divider()
                HistoryListView(model: model)
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 440)
                Divider()
                DetailView(
                    item: model.selectedItem,
                    paste: { Task { await model.pasteSelection() } },
                    favorite: { Task { await model.toggleFavoriteSelection() } },
                    rename: {
                        renameText = model.selectedItem?.customTitle
                            ?? model.selectedItem?.previewText
                            ?? ""
                        showingRename = true
                    },
                    delete: { showingDeleteConfirmation = true }
                )
                .frame(minWidth: 300, maxWidth: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
                    .padding(12)
            }
        }
        .task {
            searchFocused = true
            await model.reload()
        }
        .alert("Rename Clipboard Item", isPresented: $showingRename) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                Task { await model.renameSelection(to: renameText) }
            }
        }
        .alert("Delete Clipboard Item?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await model.deleteSelection() }
            }
        } message: {
            Text("This removes the item and its encrypted payload from this Mac.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityLabel("ClipFlow")

            TextField("Search clipboard history", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($searchFocused)
                .onSubmit { Task { await model.pasteSelection() } }
                .onChange(of: model.searchText) {
                    Task {
                        try? await Task.sleep(for: .milliseconds(120))
                        await model.reload()
                    }
                }

            if model.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Text("\(model.items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
    }
}

private struct CategorySidebar: View {
    @Bindable var model: AppModel
    @State private var showingCreateCategory = false
    @State private var categoryName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                sidebarButton("All", icon: "tray.full", selected: isAll) {
                    model.selectedKind = nil
                    model.selectedCategoryID = nil
                    model.favoritesOnly = false
                }
                sidebarButton("Favorites", icon: "star", selected: model.favoritesOnly) {
                    model.selectedKind = nil
                    model.selectedCategoryID = nil
                    model.favoritesOnly = true
                }

                Text("TYPES")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 14)
                    .padding(.horizontal, 8)

                sidebarButton("Text", icon: "text.alignleft", kind: .text)
                sidebarButton("Rich Text", icon: "textformat", kind: .richText)
                sidebarButton("Images", icon: "photo", kind: .image)
                sidebarButton("Files", icon: "doc", kind: .file)
                sidebarButton("Links", icon: "link", kind: .link)

                HStack {
                    Text("CATEGORIES")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        categoryName = ""
                        showingCreateCategory = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("New Category")
                }
                .padding(.top, 14)
                .padding(.horizontal, 8)

                ForEach(model.categories) { category in
                    sidebarButton(
                        category.name,
                        icon: "folder",
                        selected: model.selectedCategoryID == category.id
                    ) {
                        model.selectedCategoryID = category.id
                        model.selectedKind = nil
                        model.favoritesOnly = false
                    }
                    .contextMenu {
                        Button("Delete Category", role: .destructive) {
                            Task { await model.deleteCategory(category.id) }
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.55))
        .alert("New Category", isPresented: $showingCreateCategory) {
            TextField("Category name", text: $categoryName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                Task { await model.createCategory(named: categoryName) }
            }
        }
    }

    private var isAll: Bool {
        model.selectedKind == nil && model.selectedCategoryID == nil && !model.favoritesOnly
    }

    private func sidebarButton(
        _ title: String,
        icon: String,
        kind: ClipboardKind
    ) -> some View {
        sidebarButton(title, icon: icon, selected: model.selectedKind == kind) {
            model.selectedKind = kind
            model.selectedCategoryID = nil
            model.favoritesOnly = false
        }
    }

    private func sidebarButton(
        _ title: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            Task { await model.reload() }
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .frame(height: 32)
                .background(selected ? Color.accentColor.opacity(0.16) : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct HistoryListView: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.items.isEmpty && !model.isLoading {
            ContentUnavailableView(
                "No Clipboard Items",
                systemImage: "doc.on.clipboard",
                description: Text(model.searchText.isEmpty
                    ? "Copied content will appear here."
                    : "No history matches this search.")
            )
        } else {
            List(model.items, selection: $model.selectedItemID) { item in
                HistoryRow(item: item)
                    .tag(item.id)
                    .contextMenu {
                        Button("Paste") { Task { await model.pasteSelection() } }
                        Button(item.isFavorite ? "Remove Favorite" : "Favorite") {
                            model.selectedItemID = item.id
                            Task { await model.toggleFavoriteSelection() }
                        }
                        if !model.categories.isEmpty {
                            Menu("Assign to Category") {
                                ForEach(model.categories) { category in
                                    Button(category.name) {
                                        model.selectedItemID = item.id
                                        Task { await model.assignSelection(to: category.id) }
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            model.selectedItemID = item.id
                            Task { await model.deleteSelection() }
                        }
                    }
            }
            .listStyle(.inset)
        }
    }
}

private struct HistoryRow: View {
    let item: ClipboardItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.symbolName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(item.kind.tint)
                .frame(width: 30, height: 30)
                .background(item.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .lineLimit(2)
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 5) {
                    Text(item.appName)
                    Text("·")
                    Text(item.updatedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

private extension ClipboardKind {
    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .image: "photo"
        case .file: "doc"
        case .link: "link"
        case .mixed: "square.stack.3d.up"
        case .unknown: "questionmark.square.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .text: .blue
        case .richText: .purple
        case .image: .green
        case .file: .orange
        case .link: .cyan
        case .mixed: .pink
        case .unknown: .gray
        }
    }
}
