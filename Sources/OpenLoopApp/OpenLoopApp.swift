import ADHDCore
import AppKit
import Darwin
import Foundation
import LocalStore
import RuleClarifier
import VaultStore

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var quickCapture: QuickCaptureController?
    private var mainWindow: MainWindowController?
    private var hotKey: GlobalHotKey?
    private var model: AppModel?
    private var pauseMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await start() }
    }

    private func start() async {
        do {
            let directory = dataDirectory()
            let service = ProcessInfo.processInfo.environment["OPENLOOP_KEYCHAIN_SERVICE"]
                ?? "dev.openloop.adhd.vault"
            let keyProvider = KeychainVaultKeyProvider(service: service)
            let repository = try EncryptedThoughtRepository(
                directory: directory,
                keyProvider: keyProvider
            )
            let loop = ThoughtLoop(repository: repository, clarifier: RuleClarificationProvider())
            let focusLoop = FocusLoop(
                repository: repository,
                composer: InterruptionSnapshotComposer(
                    contextProvider: FrontmostApplicationReferenceProvider()
                )
            )
            let model = AppModel(
                loop: loop,
                readModels: ThoughtReadModels(repository: repository),
                focusLoop: focusLoop
            )
            _ = try await DevelopmentStoreMigrator().migrateIfNeeded(
                from: directory,
                to: repository
            )
            await model.recoverPendingClarification()

            if try await runDiagnosticIfRequested(
                directory: directory,
                keyProvider: keyProvider,
                repository: repository,
                loop: loop,
                model: model
            ) {
                NSApp.terminate(nil)
                return
            }
            let quickCapture = QuickCaptureController(model: model)
            let mainWindow = MainWindowController(model: model)
            self.quickCapture = quickCapture
            self.mainWindow = mainWindow
            self.model = model
            configureMenu(quickCapture: quickCapture, mainWindow: mainWindow)
            hotKey = try GlobalHotKey { [weak quickCapture] startedAt in
                quickCapture?.show(startedAt: startedAt)
            }
        } catch {
            NSApp.presentError(error)
        }
    }

    private func runDiagnosticIfRequested(
        directory: URL,
        keyProvider: KeychainVaultKeyProvider,
        repository: EncryptedThoughtRepository,
        loop: ThoughtLoop,
        model: AppModel
    ) async throws -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let mode = arguments.first else { return false }
        switch mode {
        case "--smoke-test":
            let result = try await loop.capture(text: "todo: packaged smoke capture", at: .now)
            guard let intention = result.intention else { exit(EXIT_FAILURE) }
            let reopened = try EncryptedThoughtRepository(
                directory: directory,
                keyProvider: keyProvider
            )
            guard try await reopened.intention(id: intention.id) != nil else { exit(EXIT_FAILURE) }
            print("smoke-test=passed")
            return true

        case "--benchmark-save":
            let count = diagnosticCount(arguments)
            var latency = CaptureLatency()
            for index in 0..<count {
                let startedAt = ContinuousClock.now
                _ = try await loop.accept(text: "benchmark capture \(index)", at: .now)
                latency.record(milliseconds: Self.milliseconds(since: startedAt))
            }
            let p95 = latency.p95 ?? .infinity
            print("capture-save-p95-ms=\(p95)")
            if p95 >= 50 { exit(EXIT_FAILURE) }
            return true

        case "--benchmark-capture":
            let count = diagnosticCount(arguments)
            let controller = QuickCaptureController(model: model)
            for _ in 0..<count {
                let previousCount = controller.latency.samples.count
                controller.show()
                guard await controller.waitForSample(after: previousCount) else {
                    print("capture-visible-timeout=true")
                    exit(EXIT_FAILURE)
                }
                controller.hide()
                guard await controller.waitUntilHidden() else {
                    print("capture-hidden-timeout=true")
                    exit(EXIT_FAILURE)
                }
            }
            let p95 = controller.latency.p95 ?? .infinity
            print("capture-visible-p95-ms=\(p95)")
            if p95 >= 100 { exit(EXIT_FAILURE) }
            return true

        case "--hotkey-test":
            let hotKey = try GlobalHotKey { _ in }
            withExtendedLifetime(hotKey) {
                print("hotkey-registration=passed")
            }
            return true

        default:
            return false
        }
    }

    private func diagnosticCount(_ arguments: [String]) -> Int {
        guard arguments.count > 1, let value = Int(arguments[1]), value > 0 else { return 100 }
        return value
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }

    @objc private func showCapture() { quickCapture?.show() }
    @objc private func showNow() { mainWindow?.show(tab: 0) }
    @objc private func showReturn() { mainWindow?.show(tab: 1) }
    @objc private func showLater() { mainWindow?.show(tab: 2) }
    @objc private func pauseOrContinue() {
        guard let model, let item = model.now, let focus = item.focus else { return }
        Task {
            if focus.state == .paused {
                await model.continueFocus(item.intentionID)
            } else if focus.state == .active {
                await model.pauseFocus(item.intentionID)
            }
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func configureMenu(
        quickCapture: QuickCaptureController,
        mainWindow: MainWindowController
    ) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "OpenLoop")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Capture", action: #selector(showCapture), keyEquivalent: "")
        menu.addItem(withTitle: "Now", action: #selector(showNow), keyEquivalent: "")
        let pauseItem = menu.addItem(
            withTitle: "Pause",
            action: #selector(pauseOrContinue),
            keyEquivalent: ""
        )
        pauseItem.isEnabled = false
        pauseMenuItem = pauseItem
        menu.addItem(withTitle: "Return", action: #selector(showReturn), keyEquivalent: "")
        menu.addItem(withTitle: "Later", action: #selector(showLater), keyEquivalent: "")
        menu.addItem(.separator())
        let privateMode = NSMenuItem(
            title: "Private Mode — no sensing active",
            action: nil,
            keyEquivalent: ""
        )
        privateMode.state = .on
        privateMode.isEnabled = false
        menu.addItem(privateMode)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit OpenLoop", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let pauseMenuItem else { return }
        switch model?.now?.focus?.state {
        case .active:
            pauseMenuItem.title = "Pause"
            pauseMenuItem.isEnabled = true
        case .paused:
            pauseMenuItem.title = "Continue"
            pauseMenuItem.isEnabled = true
        default:
            pauseMenuItem.title = "Pause"
            pauseMenuItem.isEnabled = false
        }
    }

    private func dataDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["OPENLOOP_DATA_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenLoopADHD", isDirectory: true)
    }
}

@main
struct OpenLoopApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        _ = delegate
    }
}
