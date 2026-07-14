import AppKit
import ClipFlowCore
import ClipFlowStorage
import ClipFlowSystem
import ClipFlowUI
import CryptoKit
import SwiftUI

@main
struct ClipFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: FloatingPanelController?
    private var hotKeyController: GlobalHotKeyController?
    private var monitor: PasteboardMonitor?
    private var pasteService: AppPasteService?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindowController?
    private var settingsModel: SettingsModel?
    private let loginItemService = LoginItemService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let arguments = CommandLine.arguments
        if VisualAcceptanceConfiguration.isProbe(arguments: arguments) {
            FileHandle.standardOutput.write(
                Data("CLIPFLOW_VISUAL_ACCEPTANCE_V1\n".utf8)
            )
            NSApp.terminate(nil)
            return
        }
        let visualAcceptanceConfiguration = VisualAcceptanceConfiguration.validated(
            environment: environment,
            arguments: arguments
        )
        #else
        let visualAcceptanceConfiguration: VisualAcceptanceConfiguration? = nil
        #endif

        NSApp.setActivationPolicy(.accessory)

        do {
            let support = try Self.applicationSupportDirectory()
            let runtimeDefaults = try Self.runtimeUserDefaults(
                visualAcceptanceConfiguration: visualAcceptanceConfiguration
            )
            let settings = SettingsModel(store: runtimeDefaults)
            let keyData = try Self.databaseKey(applicationSupport: support)
            let database = try SQLCipherDatabase(
                url: support.appendingPathComponent("ClipFlow.sqlite"),
                key: keyData
            )
            let externalStore = ExternalPayloadStore(
                root: support.appendingPathComponent("Payloads", isDirectory: true),
                key: SymmetricKey(data: keyData)
            )
            let repository = try ClipboardRepository(
                database: database,
                externalPayloadStore: externalStore,
                externalThresholdBytes: settings.externalPayloadThresholdMB * 1_048_576
            )
            let clipboardNormalizer = ClipboardNormalizer(
                maxRepresentationBytes: 25 * 1_024 * 1_024,
                maxCaptureBytes: 100 * 1_024 * 1_024
            )
            _ = try repository.reclassifyStoredItems(using: clipboardNormalizer)
            #if DEBUG
            if environment["CLIPFLOW_SEED_DEMO"] == "1",
               let developmentDataDirectory = environment["CLIPFLOW_DEVELOPMENT_DATA_DIR"],
               !developmentDataDirectory.isEmpty {
                let normalizer = ClipboardNormalizer(
                    maxRepresentationBytes: 5 * 1_024 * 1_024,
                    maxCaptureBytes: 10 * 1_024 * 1_024
                )
                for fixture in DevelopmentDemoData.fixtures(
                    now: Self.developmentDemoDate(environment: environment),
                    existingFileURL: Self.developmentDemoFileURL(
                        environment: environment,
                        fallbackDirectory: support
                    )
                ) {
                    _ = try repository.upsert(
                        normalizer.normalize(fixture.capture),
                        itemID: fixture.id,
                        timestamp: fixture.capturedAt
                    )
                }
            }
            #endif
            let clipboard = SystemClipboard()
            let coordinator = PasteCoordinator(
                writer: clipboard,
                accessibility: SystemAccessibilityPoster(),
                activator: SystemApplicationActivator()
            )
            let pasteService = AppPasteService(
                repository: repository,
                coordinator: coordinator,
                modeResolver: PasteModeResolver(
                    defaultMode: PasteMode(rawValue: settings.defaultPasteMode) ?? .original,
                    overrides: [:]
                )
            )
            let itemIntegrations = AppItemIntegrationService(
                repository: repository,
                settings: settings,
                clipboard: clipboard
            )
            let visualService = AppClipboardVisualService(repository: repository)
            let model = AppModel(
                repository: repository,
                pasteService: pasteService,
                itemIntegrations: itemIntegrations,
                visualService: visualService
            )
            #if DEBUG
            let browserService: any BrowserTabServing =
                visualAcceptanceConfiguration != nil || environment["CLIPFLOW_BROWSER_EMPTY"] == "1"
                    ? DevelopmentEmptyBrowserTabService()
                    : BrowserAutomation()
            #else
            let browserService: any BrowserTabServing = BrowserAutomation()
            #endif
            let browserModel = BrowserTabModel(service: browserService)
            let inputState = PanelInputStateStore()
            #if DEBUG
            if ProcessInfo.processInfo.environment["CLIPFLOW_SHOW_BROWSER_TABS"] == "1" {
                browserModel.isShowing = true
            }
            #endif
            let panelController = FloatingPanelController(
                rootView: AnyView(
                    ClipFlowRootView(
                        model: model,
                        settings: settings,
                        browserModel: browserModel,
                        inputState: inputState,
                        userDefaults: runtimeDefaults,
                        showSettings: { [weak self] in self?.showSettings() }
                    )
                ),
                inputState: inputState,
                frameDefaults: runtimeDefaults,
                handleCommand: { [weak self] action in
                    self?.handlePanelCommand(
                        action,
                        model: model,
                        browserModel: browserModel,
                        inputState: inputState
                    )
                }
            )
            let hotKeyController: GlobalHotKeyController?
            if visualAcceptanceConfiguration == nil {
                let controller = GlobalHotKeyController()
                try? controller.register(shortcut: settings.shortcut) { [weak self] in
                    self?.togglePanel()
                }
                hotKeyController = controller
            } else {
                hotKeyController = nil
            }

            let pasteboardMonitor: PasteboardMonitor?
            if visualAcceptanceConfiguration == nil {
                let monitor = PasteboardMonitor(pasteboard: clipboard)
                Task {
                    await monitor.start { capture in
                        do {
                            let normalized = try clipboardNormalizer.normalize(capture)
                            _ = try repository.upsert(normalized)
                            await model.reload()
                        } catch ClipboardNormalizationError.noUsablePayload {
                            return
                        } catch {
                            return
                        }
                    }
                }
                pasteboardMonitor = monitor
            } else {
                pasteboardMonitor = nil
            }

            self.panelController = panelController
            self.hotKeyController = hotKeyController
            self.monitor = pasteboardMonitor
            self.pasteService = pasteService
            self.settingsModel = settings
            createStatusItem()
            capturePasteTarget()
            if let visualAcceptanceConfiguration {
                try Self.writeVisualAcceptanceReadyFile(
                    configuration: visualAcceptanceConfiguration
                )
            }
            panelController.show()
            #if DEBUG
            if ProcessInfo.processInfo.environment["CLIPFLOW_SHOW_PREVIEW"] == "1" {
                Task {
                    await model.reload()
                    if let previewableItem = model.items.first(where: {
                        $0.kind == .image || $0.kind == .file
                    }) {
                        model.selectedItemID = previewableItem.id
                    }
                    model.previewSelection()
                }
            }
            if ProcessInfo.processInfo.environment["CLIPFLOW_SHOW_SETTINGS"] == "1" {
                showSettings()
            }
            #endif
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = L10n.string("app.startup.error.title")
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor {
            Task { await monitor.stop() }
        }
        hotKeyController?.unregister()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let settingsModel else { return }
        Task { await settingsModel.refreshPermissions() }
    }

    private func togglePanel() {
        if panelController?.window?.isVisible == true {
            panelController?.hide()
        } else {
            capturePasteTarget()
            panelController?.show()
        }
    }

    private func capturePasteTarget() {
        let application = NSWorkspace.shared.frontmostApplication
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let target: PasteTarget? = if let application,
                                     application.processIdentifier != ownPID {
            PasteTarget(
                processIdentifier: application.processIdentifier,
                bundleID: application.bundleIdentifier
            )
        } else {
            nil
        }
        if let pasteService {
            Task { await pasteService.setTarget(target) }
        }
    }

    private func handlePanelCommand(
        _ action: PanelCommandAction,
        model: AppModel,
        browserModel: BrowserTabModel,
        inputState: PanelInputStateStore
    ) {
        switch action {
        case .passThrough:
            return
        case .previewSelection:
            if !browserModel.isShowing {
                model.previewSelection()
            }
        case .pasteSelection:
            Task {
                if browserModel.isShowing {
                    await browserModel.activateSelection()
                } else {
                    await model.pasteSelection()
                }
            }
        case .pasteSelectionAsPlainText:
            Task {
                if browserModel.isShowing {
                    await browserModel.activateSelection()
                } else {
                    await model.pasteSelectionAsPlainText()
                }
            }
        case .clearSearch:
            inputState.searchText = ""
            if browserModel.isShowing {
                browserModel.searchText = ""
                if browserModel.selectedTab == nil {
                    browserModel.selectedTabID = browserModel.filteredTabs.first?.id
                }
            } else {
                model.searchText = ""
                Task { await model.reload() }
            }
        case .dismissPanel:
            panelController?.hide()
        case .selectPrevious:
            if browserModel.isShowing {
                moveBrowserSelection(in: browserModel, by: -1)
                inputState.requestBrowserFocus(browserModel.selectedTabID)
            } else {
                model.selectPrevious()
                inputState.requestHistoryFocus(model.selectedItemID)
            }
        case .selectNext:
            if browserModel.isShowing {
                moveBrowserSelection(in: browserModel, by: 1)
                inputState.requestBrowserFocus(browserModel.selectedTabID)
            } else {
                model.selectNext()
                inputState.requestHistoryFocus(model.selectedItemID)
            }
        }
    }

    private func moveBrowserSelection(in model: BrowserTabModel, by offset: Int) {
        let tabs = model.filteredTabs
        guard !tabs.isEmpty else {
            model.selectedTabID = nil
            return
        }
        let currentIndex = model.selectedTabID.flatMap { selectedID in
            tabs.firstIndex { $0.id == selectedID }
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), tabs.count - 1)
        model.selectedTabID = tabs[nextIndex].id
    }

    private func createStatusItem() {
        guard settingsModel?.showStatusBarItem != false else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: L10n.string("app.name")
        )
        let menu = NSMenu()
        let showItem = NSMenuItem(
            title: L10n.string("menu.show"),
            action: #selector(showPanelFromMenu),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)
        let settingsItem = NSMenuItem(
            title: L10n.string("menu.settings"),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: L10n.string("menu.quit"),
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func showPanelFromMenu() {
        if panelController?.window?.isVisible != true {
            capturePasteTarget()
            panelController?.show()
        }
    }

    @objc private func showSettings() {
        guard let settingsModel else { return }
        if let settingsWindow {
            settingsWindow.showWindow(nil)
            settingsWindow.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.string("settings.window.title")
        window.minSize = NSSize(width: 560, height: 520)
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: SettingsWindowRootView(
                model: settingsModel,
                loginItemService: loginItemService
            )
        )
        let controller = NSWindowController(window: window)
        settingsWindow = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private static func applicationSupportDirectory() throws -> URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["CLIPFLOW_DEVELOPMENT_DATA_DIR"],
           !override.isEmpty {
            let directory = URL(fileURLWithPath: override, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
        #endif
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        #if DEBUG
        let directoryName = "ClipFlow-Development"
        #else
        let directoryName = "ClipFlow"
        #endif
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func databaseKey(applicationSupport: URL) throws -> Data {
        #if DEBUG
        let keyURL = applicationSupport.appendingPathComponent("development-key", isDirectory: false)
        if let data = try? Data(contentsOf: keyURL), data.count == 32 {
            return data
        }
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        try key.write(to: keyURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: keyURL.path
        )
        return key
        #else
        return try KeychainKeyStore(
            service: "local.clipflow.app",
            account: "database-key"
        ).loadOrCreate()
        #endif
    }

    private static func runtimeUserDefaults(
        visualAcceptanceConfiguration: VisualAcceptanceConfiguration?
    ) throws -> UserDefaults {
        guard let configuration = visualAcceptanceConfiguration else {
            return .standard
        }

        let tokenDigest = SHA256.hash(data: Data(configuration.token.utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        let suiteName = "local.clipflow.visual-acceptance.\(tokenDigest)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw VisualAcceptanceSetupError.defaultsUnavailable
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(configuration.appearanceMode.rawValue, forKey: "appearanceMode")
        defaults.set(configuration.listDensity.rawValue, forKey: "listDensity")
        defaults.set(
            configuration.browserTabManagementEnabled,
            forKey: "browserTabManagementEnabled"
        )
        defaults.set(false, forKey: "showStatusBarItem")
        defaults.set(false, forKey: "launchAtLogin")
        defaults.set(false, forKey: "autoCheckUpdatesEnabled")
        defaults.set(true, forKey: "hasCompletedOnboarding")
        return defaults
    }

    private static func writeVisualAcceptanceReadyFile(
        configuration: VisualAcceptanceConfiguration
    ) throws {
        let readyFile = URL(
            fileURLWithPath: configuration.dataDirectory,
            isDirectory: true
        ).appendingPathComponent(".visual-acceptance-ready", isDirectory: false)
        try Data(configuration.token.utf8).write(to: readyFile, options: .atomic)
    }

    #if DEBUG
    private static func developmentDemoFileURL(
        environment: [String: String],
        fallbackDirectory: URL
    ) -> URL {
        guard let value = environment["CLIPFLOW_DEMO_FILE_URL"], !value.isEmpty else {
            return fallbackDirectory.appendingPathComponent("ClipFlow.sqlite")
        }
        if let fileURL = URL(string: value), fileURL.isFileURL {
            return fileURL
        }
        return URL(fileURLWithPath: value)
    }

    private static func developmentDemoDate(environment: [String: String]) -> Date {
        guard let value = environment["CLIPFLOW_DEMO_NOW"],
              let epochSeconds = TimeInterval(value) else {
            return Date()
        }
        return Date(timeIntervalSince1970: epochSeconds)
    }
    #endif
}

private struct SettingsWindowRootView: View {
    @Bindable var model: SettingsModel
    let loginItemService: LoginItemService

    var body: some View {
        SettingsView(model: model, loginItemService: loginItemService)
            .preferredColorScheme(model.appearanceMode.colorScheme)
            .environment(\.locale, L10n.locale)
    }
}

private enum VisualAcceptanceSetupError: LocalizedError {
    case defaultsUnavailable

    var errorDescription: String? {
        L10n.string("app.startup.error.title")
    }
}

#if DEBUG
private struct DevelopmentEmptyBrowserTabService: BrowserTabServing {
    func status(for browser: BrowserKind) -> BrowserAutomationStatus {
        .authorized
    }

    func tabs(for browser: BrowserKind) throws -> [BrowserTab] {
        []
    }

    func activate(_ tab: BrowserTab) throws {}
}
#endif
