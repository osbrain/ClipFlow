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
        NSApp.setActivationPolicy(.accessory)

        do {
            let support = try Self.applicationSupportDirectory()
            let settings = SettingsModel()
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
            #if DEBUG
            if ProcessInfo.processInfo.environment["CLIPFLOW_SEED_DEMO"] == "1" {
                let capture = RawClipboardCapture(
                    sourceAppName: "Notes",
                    sourceBundleID: "com.apple.Notes",
                    items: [RawClipboardItem(representations: [
                        RawClipboardRepresentation(
                            type: "public.utf8-plain-text",
                            data: Data("ClipFlow preview and drag acceptance item".utf8)
                        )
                    ])]
                )
                _ = try repository.upsert(
                    ClipboardNormalizer(
                        maxRepresentationBytes: 1_024 * 1_024,
                        maxCaptureBytes: 1_024 * 1_024
                    ).normalize(capture)
                )
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
            let browserModel = BrowserTabModel(service: BrowserAutomation())
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
                        browserModel: browserModel
                    )
                )
            )
            let hotKeyController = GlobalHotKeyController()
            try? hotKeyController.register(shortcut: settings.shortcut) { [weak self] in
                self?.togglePanel()
            }

            let monitor = PasteboardMonitor(pasteboard: clipboard)
            Task {
                await monitor.start { capture in
                    do {
                        let normalized = try ClipboardNormalizer(
                            maxRepresentationBytes: 25 * 1_024 * 1_024,
                            maxCaptureBytes: 100 * 1_024 * 1_024
                        ).normalize(capture)
                        _ = try repository.upsert(normalized)
                        await model.reload()
                    } catch ClipboardNormalizationError.noUsablePayload {
                        return
                    } catch {
                        return
                    }
                }
            }

            self.panelController = panelController
            self.hotKeyController = hotKeyController
            self.monitor = monitor
            self.pasteService = pasteService
            self.settingsModel = settings
            createStatusItem()
            capturePasteTarget()
            panelController.show()
            #if DEBUG
            if ProcessInfo.processInfo.environment["CLIPFLOW_SHOW_PREVIEW"] == "1" {
                Task {
                    await model.reload()
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
            alert.messageText = "ClipFlow could not start"
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

    private func createStatusItem() {
        guard settingsModel?.showStatusBarItem != false else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "ClipFlow"
        )
        let menu = NSMenu()
        let showItem = NSMenuItem(
            title: "Show ClipFlow",
            action: #selector(showPanelFromMenu),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit ClipFlow",
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
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 470),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipFlow Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: SettingsView(model: settingsModel, loginItemService: loginItemService)
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
}
