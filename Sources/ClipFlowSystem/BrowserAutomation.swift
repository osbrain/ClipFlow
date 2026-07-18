import AppKit
import Foundation

public enum BrowserKind: String, CaseIterable, Codable, Sendable {
    case safari
    case chrome
    case edge

    public var bundleID: String {
        switch self {
        case .safari: "com.apple.Safari"
        case .chrome: "com.google.Chrome"
        case .edge: "com.microsoft.edgemac"
        }
    }

    public var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Google Chrome"
        case .edge: "Microsoft Edge"
        }
    }
}

public enum BrowserAutomationStatus: Equatable, Sendable {
    case notInstalled
    case notRunning
    case notAuthorized
    case authorized
}

public enum BrowserAutomationError: Error, Equatable, Sendable {
    case notAuthorized
    case notInstalled
    case notRunning
    case invalidResponse
    case tabChanged
    case executionFailed(String)
}

public struct BrowserTab: Identifiable, Equatable, Sendable {
    public let browser: BrowserKind
    public let windowIndex: Int
    public let tabIndex: Int
    public let title: String
    public let url: String

    public var id: String {
        "\(browser.rawValue):\(windowIndex):\(tabIndex):\(url)"
    }
}

public struct BrowserTabSnapshot: Equatable, Sendable {
    public let status: BrowserAutomationStatus
    public let tabs: [BrowserTab]

    public init(status: BrowserAutomationStatus, tabs: [BrowserTab] = []) {
        self.status = status
        self.tabs = tabs
    }
}

public protocol BrowserWorkspaceProviding: Sendable {
    func isInstalled(_ browser: BrowserKind) -> Bool
    func isRunning(_ browser: BrowserKind) -> Bool
}

public protocol AppleEventRunning: Sendable {
    func run(script: String, arguments: [String]) throws -> String
}

public struct BrowserAutomation: Sendable {
    private let workspace: any BrowserWorkspaceProviding
    private let runner: any AppleEventRunning

    public init(
        workspace: any BrowserWorkspaceProviding = SystemBrowserWorkspace(),
        runner: any AppleEventRunning = OsaScriptRunner()
    ) {
        self.workspace = workspace
        self.runner = runner
    }

    public func status(for browser: BrowserKind) -> BrowserAutomationStatus {
        snapshot(for: browser).status
    }

    public func snapshot(for browser: BrowserKind) -> BrowserTabSnapshot {
        guard workspace.isInstalled(browser) else {
            return BrowserTabSnapshot(status: .notInstalled)
        }
        guard workspace.isRunning(browser) else {
            return BrowserTabSnapshot(status: .notRunning)
        }
        do {
            return BrowserTabSnapshot(status: .authorized, tabs: try tabs(for: browser))
        } catch BrowserAutomationError.notAuthorized {
            return BrowserTabSnapshot(status: .notAuthorized)
        } catch {
            return BrowserTabSnapshot(status: .notAuthorized)
        }
    }

    public func tabs(for browser: BrowserKind) throws -> [BrowserTab] {
        guard workspace.isInstalled(browser) else {
            throw BrowserAutomationError.notInstalled
        }
        guard workspace.isRunning(browser) else {
            throw BrowserAutomationError.notRunning
        }

        let output = try runner.run(
            script: Self.enumerateTabsScript(for: browser),
            arguments: [browser.bundleID]
        )
        guard let data = output.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([RawBrowserTab].self, from: data) else {
            throw BrowserAutomationError.invalidResponse
        }
        return decoded.map {
            BrowserTab(
                browser: browser,
                windowIndex: $0.windowIndex,
                tabIndex: $0.tabIndex,
                title: $0.title,
                url: $0.url
            )
        }
    }

    public func activate(_ tab: BrowserTab) throws {
        let output = try runner.run(
            script: Self.activateTabScript(for: tab.browser),
            arguments: [
                tab.browser.bundleID,
                String(tab.windowIndex),
                String(tab.tabIndex),
                tab.title,
                tab.url
            ]
        )
        guard output.trimmingCharacters(in: .whitespacesAndNewlines) == "activated" else {
            throw BrowserAutomationError.tabChanged
        }
    }

    private static func enumerateTabsScript(for browser: BrowserKind) -> String {
        let titleProperty = browser == .safari ? "name" : "title"
        return """
        function run(argv) {
            const app = Application(argv[0]);
            const result = [];
            const windows = app.windows();
            for (let wi = 0; wi < windows.length; wi++) {
                const tabs = windows[wi].tabs();
                for (let ti = 0; ti < tabs.length; ti++) {
                    result.push({
                        windowIndex: wi,
                        tabIndex: ti,
                        title: String(tabs[ti].\(titleProperty)() || ""),
                        url: String(tabs[ti].url() || "")
                    });
                }
            }
            return JSON.stringify(result);
        }
        """
    }

    private static func activateTabScript(for browser: BrowserKind) -> String {
        let titleProperty = browser == .safari ? "name" : "title"
        return """
        function run(argv) {
            const bundleID = argv[0];
            const wi = Number(argv[1]);
            const ti = Number(argv[2]);
            const expectedTitle = argv[3];
            const expectedURL = argv[4];
            const app = Application(bundleID);
            const windows = app.windows();
            if (wi < 0 || wi >= windows.length) return "changed";
            const tabs = windows[wi].tabs();
            if (ti < 0 || ti >= tabs.length) return "changed";
            const tab = tabs[ti];
            if (String(tab.\(titleProperty)() || "") !== expectedTitle ||
                String(tab.url() || "") !== expectedURL) return "changed";
            if (bundleID === "com.apple.Safari") {
                windows[wi].currentTab = tab;
            } else {
                windows[wi].activeTabIndex = ti + 1;
            }
            windows[wi].index = 1;
            app.activate();
            return "activated";
        }
        """
    }
}

public struct SystemBrowserWorkspace: BrowserWorkspaceProviding {
    public init() {}

    public func isInstalled(_ browser: BrowserKind) -> Bool {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: browser.bundleID
        ) != nil
    }

    public func isRunning(_ browser: BrowserKind) -> Bool {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: browser.bundleID
        ).contains { !$0.isTerminated }
    }
}

public final class OsaScriptRunner: AppleEventRunning, @unchecked Sendable {
    public init() {}

    public func run(script: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script, "--"] + arguments
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            throw BrowserAutomationError.executionFailed(error.localizedDescription)
        }
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            if errorText.contains("-1743") ||
                errorText.localizedCaseInsensitiveContains("not authorized") ||
                errorText.localizedCaseInsensitiveContains("not permitted") {
                throw BrowserAutomationError.notAuthorized
            }
            throw BrowserAutomationError.executionFailed(
                errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return (String(data: outputData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RawBrowserTab: Decodable {
    let windowIndex: Int
    let tabIndex: Int
    let title: String
    let url: String
}
