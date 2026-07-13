import ClipFlowCore
import ClipFlowSystem
import SwiftUI

struct DetailView: View {
    let item: ClipboardItem?
    let paste: () -> Void
    let preview: () -> Void
    let favorite: () -> Void
    let rename: () -> Void
    let delete: () -> Void
    let applicationActions: [ApplicationAction]
    let performApplicationAction: (ApplicationAction) -> Void

    var body: some View {
        Group {
            if let item {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayTitle)
                                .font(.headline)
                                .lineLimit(2)
                            Text(item.kind.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Button(action: preview) {
                                Image(systemName: "eye")
                            }
                            .help("Quick Look")
                            Button(action: favorite) {
                                Image(systemName: item.isFavorite ? "star.fill" : "star")
                            }
                            .help(item.isFavorite ? "Remove Favorite" : "Favorite")
                            Button(action: rename) {
                                Image(systemName: "pencil")
                            }
                            .help("Rename")
                            Button(role: .destructive, action: delete) {
                                Image(systemName: "trash")
                            }
                            .help("Delete")
                            Button(action: paste) {
                                Label("Paste", systemImage: "arrow.down.doc")
                            }
                            .keyboardShortcut(.return, modifiers: [])
                        }
                    }
                    .padding(16)

                    Divider()

                    ScrollView {
                        Text(item.previewText)
                            .font(.system(size: 14))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(18)
                    }

                    if !applicationActions.isEmpty {
                        Divider()
                        HStack(spacing: 8) {
                            ForEach(applicationActions, id: \.self) { action in
                                Button {
                                    performApplicationAction(action)
                                } label: {
                                    Label(action.displayName, systemImage: action.symbolName)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    Divider()

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                        metadata("Source", item.appName)
                        metadata("Created", item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        metadata("Updated", item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        metadata("Size", ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file))
                    }
                    .font(.caption)
                    .padding(16)
                }
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "cursorarrow.click",
                    description: Text("Select an item to inspect its details.")
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }

    @ViewBuilder
    private func metadata(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
