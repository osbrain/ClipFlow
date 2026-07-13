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
            Text("ClipFlow Settings")
                .frame(width: 420, height: 240)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: FloatingPanelController?
    private var hotKeyController: GlobalHotKeyController?
    private var monitor: PasteboardMonitor?
    private var pasteService: AppPasteService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let support = try Self.applicationSupportDirectory()
            let keyData = try KeychainKeyStore(
                service: "local.clipflow.app",
                account: "database-key"
            ).loadOrCreate()
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
                externalThresholdBytes: 1_048_576
            )
            let clipboard = SystemClipboard()
            let coordinator = PasteCoordinator(
                writer: clipboard,
                accessibility: SystemAccessibilityPoster(),
                activator: SystemApplicationActivator()
            )
            let pasteService = AppPasteService(
                repository: repository,
                coordinator: coordinator,
                modeResolver: PasteModeResolver(defaultMode: .original, overrides: [:])
            )
            let model = AppModel(repository: repository, pasteService: pasteService)
            let panelController = FloatingPanelController(
                rootView: AnyView(MainPanelView(model: model))
            )
            let hotKeyController = GlobalHotKeyController()
            try? hotKeyController.register(shortcut: .commandShiftV) { [weak self] in
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
            capturePasteTarget()
            panelController.show()
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

    private static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("ClipFlow", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
