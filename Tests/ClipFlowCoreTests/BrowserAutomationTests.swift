import Foundation
import Testing
@testable import ClipFlowSystem
@testable import ClipFlowUI

@Suite("Browser automation")
struct BrowserAutomationTests {
    @Test("separates not installed not running and denied statuses")
    func separatesBrowserStatuses() {
        let workspace = FakeBrowserWorkspace(
            installed: [.chrome],
            running: []
        )
        let runner = FakeAppleEventRunner()
        let service = BrowserAutomation(workspace: workspace, runner: runner)

        #expect(service.status(for: .edge) == .notInstalled)
        #expect(service.status(for: .chrome) == .notRunning)

        workspace.running = [.chrome]
        runner.error = .notAuthorized
        #expect(service.status(for: .chrome) == .notAuthorized)
    }

    @Test("decodes browser tab coordinates title and URL")
    func decodesBrowserTabs() throws {
        let workspace = FakeBrowserWorkspace(
            installed: [.chrome],
            running: [.chrome]
        )
        let runner = FakeAppleEventRunner()
        runner.output = """
        [{"windowIndex":0,"tabIndex":2,"title":"OpenAI","url":"https://openai.com"}]
        """
        let service = BrowserAutomation(workspace: workspace, runner: runner)

        let tabs = try service.tabs(for: .chrome)

        #expect(tabs.count == 1)
        #expect(tabs.first?.browser == .chrome)
        #expect(tabs.first?.windowIndex == 0)
        #expect(tabs.first?.tabIndex == 2)
        #expect(tabs.first?.title == "OpenAI")
        #expect(tabs.first?.url == "https://openai.com")
    }

    @Test("uses browser-specific tab title properties")
    func usesBrowserSpecificTabTitleProperties() throws {
        let workspace = FakeBrowserWorkspace(
            installed: [.safari, .chrome],
            running: [.safari, .chrome]
        )
        let runner = FakeAppleEventRunner()
        let service = BrowserAutomation(workspace: workspace, runner: runner)

        _ = try service.tabs(for: .safari)
        let safariScript = try #require(runner.lastScript)
        #expect(safariScript.contains("tabs[ti].name()"))
        #expect(!safariScript.contains("tabs[ti].title()"))

        _ = try service.tabs(for: .chrome)
        let chromeScript = try #require(runner.lastScript)
        #expect(chromeScript.contains("tabs[ti].title()"))
        #expect(!chromeScript.contains("tabs[ti].name()"))
    }

    @Test("refuses to activate a tab whose position now has different content")
    func refusesChangedTabActivation() {
        let workspace = FakeBrowserWorkspace(
            installed: [.chrome],
            running: [.chrome]
        )
        let runner = FakeAppleEventRunner()
        runner.output = "changed"
        let service = BrowserAutomation(workspace: workspace, runner: runner)
        let tab = BrowserTab(
            browser: .chrome,
            windowIndex: 0,
            tabIndex: 1,
            title: "Original",
            url: "https://example.com"
        )

        #expect(throws: BrowserAutomationError.tabChanged) {
            try service.activate(tab)
        }
    }

    @Test("keeps activation failure visible after refreshing stale tabs")
    @MainActor
    func keepsActivationFailureVisible() async {
        let service = FakeBrowserTabService()
        let model = BrowserTabModel(service: service)
        await model.refresh()

        await model.activateSelection()

        #expect(model.errorMessage != nil)
    }
}

private final class FakeBrowserWorkspace: BrowserWorkspaceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var installedBrowsers: Set<BrowserKind>
    private var runningBrowsers: Set<BrowserKind>

    init(installed: Set<BrowserKind>, running: Set<BrowserKind>) {
        installedBrowsers = installed
        runningBrowsers = running
    }

    var running: Set<BrowserKind> {
        get { lock.withLock { runningBrowsers } }
        set { lock.withLock { runningBrowsers = newValue } }
    }

    func isInstalled(_ browser: BrowserKind) -> Bool {
        lock.withLock { installedBrowsers.contains(browser) }
    }

    func isRunning(_ browser: BrowserKind) -> Bool {
        lock.withLock { runningBrowsers.contains(browser) }
    }
}

private final class FakeAppleEventRunner: AppleEventRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var storedOutput = "[]"
    private var storedError: BrowserAutomationError?
    private var storedLastScript: String?

    var output: String {
        get { lock.withLock { storedOutput } }
        set { lock.withLock { storedOutput = newValue } }
    }

    var error: BrowserAutomationError? {
        get { lock.withLock { storedError } }
        set { lock.withLock { storedError = newValue } }
    }

    var lastScript: String? {
        lock.withLock { storedLastScript }
    }

    func run(script: String, arguments: [String]) throws -> String {
        try lock.withLock {
            storedLastScript = script
            if let storedError { throw storedError }
            return storedOutput
        }
    }
}

private final class FakeBrowserTabService: BrowserTabServing, @unchecked Sendable {
    private let tab = BrowserTab(
        browser: .chrome,
        windowIndex: 0,
        tabIndex: 0,
        title: "OpenAI",
        url: "https://openai.com"
    )

    func status(for browser: BrowserKind) -> BrowserAutomationStatus {
        browser == .chrome ? .authorized : .notRunning
    }

    func tabs(for browser: BrowserKind) throws -> [BrowserTab] {
        browser == .chrome ? [tab] : []
    }

    func activate(_ tab: BrowserTab) throws {
        throw BrowserAutomationError.tabChanged
    }
}
