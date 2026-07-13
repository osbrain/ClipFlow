import ClipFlowSystem
import SwiftUI

struct BrowserTabListView: View {
    @Bindable var model: BrowserTabModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Browser Tabs")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh Browser Tabs")
            }
            .padding(.horizontal, 14)
            .frame(height: 42)

            Divider()

            if model.filteredTabs.isEmpty {
                BrowserTabEmptyState(model: model)
            } else {
                List(model.filteredTabs, selection: $model.selectedTabID) { tab in
                    HStack(spacing: 10) {
                        Image(systemName: tab.browser.symbolName)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tab.title).lineLimit(1)
                            Text(tab.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(minHeight: 48)
                    .tag(tab.id)
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct BrowserTabEmptyState: View {
    @Bindable var model: BrowserTabModel

    var body: some View {
        if !model.searchText.isEmpty && !model.tabs.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            VStack(spacing: 18) {
                ContentUnavailableView(
                    "No Browser Tabs",
                    systemImage: "macwindow.on.rectangle",
                    description: Text("Open a browser or allow Automation access to list its tabs.")
                )
                VStack(spacing: 8) {
                    ForEach(BrowserKind.allCases, id: \.self) { browser in
                        HStack(spacing: 10) {
                            Image(systemName: browser.symbolName)
                                .frame(width: 20)
                            Text(browser.displayName)
                            Spacer()
                            Text(model.statuses[browser, default: .notRunning].displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct BrowserTabDetailView: View {
    @Bindable var model: BrowserTabModel

    var body: some View {
        if let tab = model.selectedTab {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: tab.browser.symbolName)
                        .font(.title2)
                    Text(tab.browser.displayName)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await model.activateSelection() }
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                    .keyboardShortcut(.return, modifiers: [])
                }
                Text(tab.title)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                Text(tab.url)
                    .foregroundStyle(.blue)
                    .textSelection(.enabled)
                Spacer()
                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        } else {
            ContentUnavailableView(
                "No Tab Selected",
                systemImage: "cursorarrow.click",
                description: Text("Select a browser tab to inspect it.")
            )
        }
    }
}

private extension BrowserKind {
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
        case .notInstalled: "Not installed"
        case .notRunning: "Not running"
        case .notAuthorized: "Access required"
        case .authorized: "Connected"
        }
    }
}
