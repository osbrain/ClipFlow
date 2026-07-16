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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panelController: FloatingPanelController?
    private var hotKeyController: GlobalHotKeyController?
    private var monitor: PasteboardMonitor?
    private var pasteService: AppPasteService?
    private var settingsCoordinator: AppSettingsCoordinator?
    private var logger: LocalLogger?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindowController?
    private var settingsModel: SettingsModel?
    private var appModel: AppModel?
    private var historyRepository: (any HistoryRepository)?
    private var isRestoringRuntimeSettings = false
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
            let logURL = support.appendingPathComponent("ClipFlow.log")
            #if DEBUG
            let permissionStatus: any PermissionStatusProviding =
                visualAcceptanceConfiguration?.showsOnboarding == true
                    ? DevelopmentFixedPermissionStatus(
                        isTrusted: visualAcceptanceConfiguration?.accessibilityTrusted == true
                    )
                    : SystemPermissionStatus()
            #else
            let permissionStatus: any PermissionStatusProviding = SystemPermissionStatus()
            #endif
            let settings = SettingsModel(
                store: runtimeDefaults,
                permissions: permissionStatus,
                diagnosticLogURL: logURL
            )
            L10n.configure(language: settings.appLanguage)
            let logger = LocalLogger(
                fileURL: logURL,
                enabled: settings.debugLoggingEnabled
            )
            do {
                try loginItemService.setEnabled(settings.launchAtLogin)
            } catch {
                settings.reportRuntimeError(
                    L10n.format("settings.error.loginItem", error.localizedDescription)
                )
            }
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
            let retentionPolicyStore = AppRetentionPolicyStore(
                policy: settings.runtimeSnapshot.retention.policy
            )
            let startupDeleted = try repository.applyRetention(retentionPolicyStore.current())
            Task {
                await logger.log("startup")
                await logger.log(
                    "retention_cleanup",
                    metadata: ["deletedCount": "\(startupDeleted.count)"]
                )
            }
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
            let inputState = PanelInputStateStore(
                isPresentingOnboarding: !runtimeDefaults.bool(
                    forKey: "hasCompletedOnboarding"
                )
            )
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
                do {
                    try controller.register(shortcut: settings.shortcut) { [weak self] in
                        self?.togglePanel()
                    }
                } catch {
                    settings.reportRuntimeError(
                        L10n.format("settings.error.shortcut", error.localizedDescription)
                    )
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
                            let deleted = try repository.applyRetention(
                                retentionPolicyStore.current()
                            )
                            await logger.log(
                                "capture",
                                metadata: [
                                    "kind": normalized.kind.rawValue,
                                    "byteCount": "\(normalized.byteSize)"
                                ]
                            )
                            if !deleted.isEmpty {
                                await logger.log(
                                    "retention_cleanup",
                                    metadata: ["deletedCount": "\(deleted.count)"]
                                )
                            }
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
            self.appModel = model
            self.historyRepository = repository
            self.logger = logger
            self.settingsCoordinator = AppSettingsCoordinator(
                repository: repository,
                pasteService: pasteService,
                logger: logger,
                retentionPolicyStore: retentionPolicyStore,
                updateShortcut: { [weak self] shortcut, previous in
                    try self?.replaceShortcut(shortcut, restoring: previous)
                },
                updateStatusItem: { [weak self] enabled in
                    self?.updateStatusItem(enabled: enabled)
                },
                updateLanguage: { [weak self] language in
                    self?.updateLanguage(language)
                }
            )
            updateStatusItem(enabled: settings.showStatusBarItem)
            capturePasteTarget()
            if let visualAcceptanceConfiguration {
                try Self.writeVisualAcceptanceReadyFile(
                    configuration: visualAcceptanceConfiguration
                )
            }
            panelController.show()
            #if DEBUG
            if let selectedKind = visualAcceptanceConfiguration?.selectedKind {
                Task {
                    await model.reload()
                    model.selectedItemID = model.items.first(where: {
                        $0.kind == selectedKind
                    })?.id
                }
            }
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
        appModel?.updatePasteDestination(
            name: target == nil ? nil : application?.localizedName
        )
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
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: L10n.string("app.name")
        )
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildStatusMenu(menu)
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let records = (try? historyRepository?.search(
            SearchQuery(text: "", categoryID: nil, kind: nil, favoritesOnly: false)
        )) ?? []
        let presentation = StatusMenuPresentation(
            items: records,
            pasteDestinationName: appModel?.pasteDestinationName
        )

        menu.addItem(
            informationalMenuItem(
                title: L10n.string("app.name"),
                symbolName: "lock.shield.fill"
            )
        )
        if let shortcut = settingsModel?.shortcut {
            menu.addItem(
                informationalMenuItem(
                    title: L10n.format(
                        "menu.status.shortcut",
                        L10n.string("settings.shortcut.\(shortcut.rawValue)")
                    ),
                    symbolName: "keyboard"
                )
            )
        }
        menu.addItem(
            informationalMenuItem(
                title: L10n.format("menu.status.records", presentation.recordCount)
                    + " · " + L10n.string("menu.status.encrypted"),
                symbolName: "checkmark.seal.fill"
            )
        )
        if let pasteDestinationName = presentation.pasteDestinationName {
            menu.addItem(
                informationalMenuItem(
                    title: L10n.format("menu.status.destination", pasteDestinationName),
                    symbolName: "arrow.right.circle"
                )
            )
        }

        menu.addItem(.separator())
        menu.addItem(informationalMenuItem(title: L10n.string("menu.status.recent")))
        if presentation.recentItems.isEmpty {
            menu.addItem(
                informationalMenuItem(
                    title: L10n.string("menu.status.empty"),
                    symbolName: "doc.on.clipboard"
                )
            )
        } else {
            for recentItem in presentation.recentItems {
                let item = NSMenuItem(
                    title: L10n.format(
                        "menu.status.recentItem",
                        recentItem.menuTitle,
                        recentItem.sourceName,
                        recentItem.kind.localizedDisplayName
                    ),
                    action: #selector(revealRecentClipboardItem),
                    keyEquivalent: ""
                )
                item.target = self
                item.image = NSImage(
                    systemSymbolName: recentItem.symbolName,
                    accessibilityDescription: recentItem.kind.localizedDisplayName
                )
                item.representedObject = recentItem.id.uuidString
                item.toolTip = recentItem.title
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let showItem = NSMenuItem(
            title: L10n.string("menu.show"),
            action: #selector(showPanelFromMenu),
            keyEquivalent: ""
        )
        showItem.target = self
        showItem.image = NSImage(
            systemSymbolName: "rectangle.stack.badge.play",
            accessibilityDescription: L10n.string("menu.show")
        )
        menu.addItem(showItem)

        let settingsItem = NSMenuItem(
            title: L10n.string("menu.settings"),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: L10n.string("menu.settings")
        )
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.string("menu.quit"),
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func informationalMenuItem(
        title: String,
        symbolName: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let symbolName {
            item.image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: nil
            )
        }
        return item
    }

    private func updateStatusItem(enabled: Bool) {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        if enabled {
            createStatusItem()
        }
    }

    private func replaceShortcut(
        _ shortcut: HotKeyShortcut,
        restoring previous: HotKeyShortcut
    ) throws {
        guard let hotKeyController else { return }
        do {
            try hotKeyController.register(shortcut: shortcut) { [weak self] in
                self?.togglePanel()
            }
        } catch {
            try? hotKeyController.register(shortcut: previous) { [weak self] in
                self?.togglePanel()
            }
            throw error
        }
    }

    private func updateLanguage(_ language: AppLanguage) {
        L10n.configure(language: language)
        settingsWindow?.window?.title = L10n.string("settings.window.title")
    }

    @objc private func showPanelFromMenu() {
        StatusMenuPanelPresentation.afterMenuCloses { [weak self] in
            guard let self else { return }
            capturePasteTarget()
            panelController?.show()
        }
    }

    @objc private func revealRecentClipboardItem(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              let itemID = UUID(uuidString: identifier),
              let appModel else {
            return
        }

        appModel.searchText = ""
        appModel.apply(.all)
        Task { @MainActor [weak self, weak appModel] in
            guard let self, let appModel else { return }
            await appModel.reload()
            guard appModel.items.contains(where: { $0.id == itemID }) else { return }
            appModel.selectedItemID = itemID
            self.capturePasteTarget()
            self.panelController?.show()
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

        let window = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: SettingsWindowAppearance.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        SettingsWindowAppearance.apply(to: window)
        window.center()
        window.contentView = NSHostingView(
            rootView: SettingsWindowRootView(
                model: settingsModel,
                loginItemService: loginItemService,
                onRuntimeSettingsChange: { [weak self, weak settingsModel] previous, current in
                    Task { @MainActor in
                        guard let self, let settingsModel else { return }
                        if self.isRestoringRuntimeSettings {
                            self.isRestoringRuntimeSettings = false
                            return
                        }
                        do {
                            try await self.settingsCoordinator?.apply(
                                previous: previous,
                                current: current
                            )
                            settingsModel.clearRuntimeError()
                            settingsModel.refreshDiagnostics()
                        } catch {
                            await self.logger?.log(
                                "settings_application_error",
                                metadata: ["errorType": String(describing: type(of: error))]
                            )
                            switch error {
                            case AppSettingsCoordinatorError.shortcutRegistrationFailed(
                                let underlying
                            ):
                                self.isRestoringRuntimeSettings = true
                                settingsModel.shortcut = previous.shortcut
                                settingsModel.save()
                                settingsModel.reportRuntimeError(
                                    L10n.format(
                                        "settings.error.shortcut",
                                        underlying.localizedDescription
                                    )
                                )
                            case AppSettingsCoordinatorError.retentionFailed(let underlying):
                                settingsModel.reportRuntimeError(
                                    L10n.format(
                                        "settings.error.runtime",
                                        underlying.localizedDescription
                                    )
                                )
                            default:
                                settingsModel.reportRuntimeError(
                                    L10n.format(
                                        "settings.error.runtime",
                                        error.localizedDescription
                                    )
                                )
                            }
                        }
                    }
                }
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
        defaults.set(RetentionPreference.unlimited.rawValue, forKey: "retentionPolicy")
        defaults.set(!configuration.showsOnboarding, forKey: "hasCompletedOnboarding")
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

@MainActor
private final class SettingsWindow: NSWindow {
    override func performClose(_ sender: Any?) {
        orderOut(sender)
    }

    override func miniaturize(_ sender: Any?) {
        switch SettingsWindowMinimizeBehavior.action(
            forAccessoryApplication: NSApp.activationPolicy() == .accessory
        ) {
        case .hide:
            orderOut(sender)
        case .miniaturize:
            super.miniaturize(sender)
        }
    }
}

private struct SettingsWindowRootView: View {
    @Bindable var model: SettingsModel
    let loginItemService: LoginItemService
    let onRuntimeSettingsChange: @MainActor (
        AppSettingsRuntimeSnapshot,
        AppSettingsRuntimeSnapshot
    ) -> Void

    var body: some View {
        SettingsView(
            model: model,
            loginItemService: loginItemService,
            onRuntimeSettingsChange: onRuntimeSettingsChange
        )
            .preferredColorScheme(model.appearanceMode.colorScheme)
            .id(model.appLanguage)
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

private struct DevelopmentFixedPermissionStatus: PermissionStatusProviding {
    let isTrusted: Bool

    func isAccessibilityTrusted() -> Bool { isTrusted }
    func requestAccessibilityAuthorization() -> Bool { isTrusted }
    func resetAccessibilityAuthorization() {}
}
#endif
