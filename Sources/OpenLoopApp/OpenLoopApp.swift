import ADHDCore
import AppKit
import Carbon
import Darwin
import Foundation
import LocalStore
import RuleClarifier
import VaultStore

@MainActor
struct WorkspaceLifecycle {
    private let show: (Int) -> Void

    init(show: @escaping (Int) -> Void) {
        self.show = show
    }

    func showInitialWorkspace() {
        show(0)
    }

    @discardableResult
    func restoreWorkspace(hasVisibleWindows: Bool) -> Bool {
        guard hasVisibleWindows == false else { return false }
        show(0)
        return true
    }
}

@MainActor
private final class DiagnosticVoiceTranscriber: VoiceTranscribing {
    private var transcriptHandler: (@MainActor @Sendable (String, Bool) -> Void)?

    func requestAuthorization() async -> VoiceAuthorization { .authorized }

    func start(
        configuration: SpeechProviderConfiguration,
        onTranscript: @escaping @MainActor @Sendable (String, Bool) -> Void,
        onAudioLevel: @escaping @MainActor @Sendable (Double) -> Void,
        onFailure: @escaping @MainActor @Sendable (String) -> Void
    ) throws {
        transcriptHandler = onTranscript
    }

    func stop() { transcriptHandler = nil }
    func cancel() { transcriptHandler = nil }

    func emit(_ value: String) {
        transcriptHandler?(value, false)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var quickCapture: QuickCaptureController?
    private var mainWindow: MainWindowController?
    private var hotKey: GlobalHotKey?
    private var voiceHotKey: GlobalHotKey?
    private var voiceCapture: VoiceCaptureWindowController?
    private var model: AppModel?
    private var pauseMenuItem: NSMenuItem?
    private var contextProvider: FrontmostApplicationReferenceProvider?
    private var workspaceLifecycle: WorkspaceLifecycle?

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
            let contextProvider = FrontmostApplicationReferenceProvider()
            let focusLoop = FocusLoop(
                repository: repository,
                composer: InterruptionSnapshotComposer(
                    contextProvider: contextProvider
                )
            )
            let resurfacingLoop = ResurfacingLoop(repository: repository)
            let model = AppModel(
                loop: loop,
                readModels: ThoughtReadModels(repository: repository),
                focusLoop: focusLoop,
                resurfacingLoop: resurfacingLoop
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
            let voiceController = VoiceTranscriptionController(
                transcriber: OnDeviceSpeechTranscriber()
            ) { [weak model] transcript in
                await model?.submitCapture(transcript) ?? false
            }
            let voiceCapture = VoiceCaptureWindowController(controller: voiceController)
            self.quickCapture = quickCapture
            self.mainWindow = mainWindow
            self.voiceCapture = voiceCapture
            self.model = model
            self.contextProvider = contextProvider
            let workspaceLifecycle = WorkspaceLifecycle { [weak self] tab in
                self?.presentWorkspace(tab: tab)
            }
            self.workspaceLifecycle = workspaceLifecycle
            configureMenu(quickCapture: quickCapture, mainWindow: mainWindow)
            await contextProvider.snapshot()
            await model.refreshContext(await contextProvider.currentContext())
            mainWindow.show(tab: 0)
            do {
                hotKey = try GlobalHotKey { [weak quickCapture] startedAt in
                    quickCapture?.show(startedAt: startedAt)
                }
            } catch {
                model.commandError = "Quick Capture shortcut is unavailable. Use Capture in the menu."
            }
            do {
                voiceHotKey = try GlobalHotKey(
                    keyCode: UInt32(kVK_ANSI_R),
                    modifiers: UInt32(cmdKey | shiftKey),
                    id: 2
                ) { [weak voiceCapture] _ in
                    voiceCapture?.toggle()
                }
            } catch {
                model.resurfacingError = "Voice shortcut is unavailable. Use Record & Transcribe in the menu."
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
            let captureHotKey = try GlobalHotKey { _ in }
            let voiceHotKey = try GlobalHotKey(
                keyCode: UInt32(kVK_ANSI_R),
                modifiers: UInt32(cmdKey | shiftKey),
                id: 2
            ) { _ in }
            withExtendedLifetime((captureHotKey, voiceHotKey)) {
                print("hotkey-registration=passed")
                print("voice-hotkey-registration=passed")
            }
            return true

        case "--window-test":
            let controller = MainWindowController(model: model)
            controller.show(tab: 0)
            await Task.yield()
            guard controller.isVisibleForTesting,
                  controller.windowNumberForTesting > 0 else {
                print("window-test=failed")
                exit(EXIT_FAILURE)
            }
            print("window-test=passed")
            controller.closeForTesting()
            return true

        case "--voice-controller-test":
            let marker = "packaged on-device voice transcript marker"
            let transcriber = DiagnosticVoiceTranscriber()
            let controller = VoiceTranscriptionController(transcriber: transcriber) { value in
                do {
                    _ = try await loop.accept(text: value, at: .now)
                    return true
                } catch {
                    return false
                }
            }
            await controller.toggle()
            guard controller.state == .recording else { exit(EXIT_FAILURE) }
            transcriber.emit(marker)
            await controller.toggle()
            let voiceReopened = try EncryptedThoughtRepository(
                directory: directory,
                keyProvider: keyProvider
            )
            guard controller.state == .idle,
                  try await voiceReopened.unclarifiedCaptures().contains(where: {
                      $0.text == marker
                  }) else {
                exit(EXIT_FAILURE)
            }
            print("voice-controller-test=passed")
            return true

        case "--resurfacing-test":
            try await runResurfacingDiagnostic(
                directory: directory,
                keyProvider: keyProvider,
                repository: repository,
                loop: loop
            )
            return true

        case "--focus-interrupt-test":
            let startedAt = Date(timeIntervalSince1970: 1_723_600_000)
            let interruptedAt = startedAt.addingTimeInterval(73)
            let result = try await loop.capture(
                text: "todo: packaged focus recovery marker",
                at: startedAt
            )
            guard let intention = result.intention else { exit(EXIT_FAILURE) }
            let expectedPacket = try Self.focusDiagnosticPacket()
            let focusLoop = FocusLoop(repository: repository)
            _ = try await focusLoop.start(intention.id, at: startedAt)
            _ = try await focusLoop.interrupt(
                intention.id,
                draft: InterruptionDraft(
                    justCompleted: expectedPacket.justCompleted,
                    nextAction: expectedPacket.nextAction,
                    blocker: expectedPacket.blocker,
                    references: expectedPacket.references
                ),
                at: interruptedAt
            )
            print("focus-interrupted-id=\(intention.id.uuidString)")
            return true

        case "--focus-resume-test":
            guard arguments.count > 1, let intentionID = UUID(uuidString: arguments[1]) else {
                exit(EXIT_FAILURE)
            }
            let expectedPacket = try Self.focusDiagnosticPacket()
            guard let storedIntention = try await repository.intention(id: intentionID),
                  storedIntention.state == .interrupted,
                  storedIntention.returnPacket == expectedPacket,
                  let storedSession = try await repository.focusSessions().first(where: {
                      $0.intentionID == intentionID
                  }),
                  storedSession.state == .interrupted,
                  model.returns.contains(where: {
                      $0.intentionID == intentionID
                          && $0.nextAction == expectedPacket.nextAction
                          && $0.references == expectedPacket.references
                  }) else {
                exit(EXIT_FAILURE)
            }

            _ = try await FocusLoop(repository: repository).resume(
                intentionID,
                at: expectedPacket.capturedAt.addingTimeInterval(20)
            )
            let verified = try EncryptedThoughtRepository(
                directory: directory,
                keyProvider: keyProvider
            )
            guard let resumedIntention = try await verified.intention(id: intentionID),
                  resumedIntention.state == .active,
                  resumedIntention.nextAction == expectedPacket.nextAction,
                  resumedIntention.returnPacket == expectedPacket,
                  let resumedSession = try await verified.focusSessions().first(where: {
                      $0.intentionID == intentionID
                  }),
                  resumedSession.state == .active else {
                exit(EXIT_FAILURE)
            }
            print("focus-resume-test=passed")
            return true

        default:
            return false
        }
    }

    private func diagnosticCount(_ arguments: [String]) -> Int {
        guard arguments.count > 1, let value = Int(arguments[1]), value > 0 else { return 100 }
        return value
    }

    private func runResurfacingDiagnostic(
        directory: URL,
        keyProvider: KeychainVaultKeyProvider,
        repository: EncryptedThoughtRepository,
        loop: ThoughtLoop
    ) async throws {
        let application = try ApplicationContext(
            bundleIdentifier: "dev.openloop.packaged-context-marker",
            applicationName: "Packaged Context Marker"
        )
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let linkedResult = try await loop.capture(
            text: "todo: packaged linked resurfacing marker",
            at: date
        )
        let unrelatedResult = try await loop.capture(
            text: "todo: packaged unrelated resurfacing marker",
            at: date.addingTimeInterval(1)
        )
        let neverResult = try await loop.capture(
            text: "todo: packaged permanent suppression marker",
            at: date.addingTimeInterval(2)
        )
        guard let linked = linkedResult.intention,
              unrelatedResult.intention != nil,
              let never = neverResult.intention else {
            exit(EXIT_FAILURE)
        }
        let linkedRule = ResurfacingRule(
            intentionID: linked.id,
            application: application,
            createdAt: date.addingTimeInterval(3)
        )
        let neverRule = ResurfacingRule(
            intentionID: never.id,
            application: application,
            createdAt: date.addingTimeInterval(3)
        )
        try await repository.save(resurfacingRule: linkedRule)
        try await repository.save(resurfacingRule: neverRule)
        let resurfacingLoop = ResurfacingLoop(repository: repository)
        let context = ContextEvent(
            observedAt: date.addingTimeInterval(10),
            application: application
        )
        let first = try await resurfacingLoop.suggest(
            for: context,
            at: context.observedAt
        )
        guard first.count == 2,
              first.first?.intentionID == linked.id,
              first.first?.score == RelevanceScorer.threshold,
              first.first?.why == "Linked to Packaged Context Marker",
              first.first?.contributions.first?.label == "Application match" else {
            exit(EXIT_FAILURE)
        }
        let repeated = try await resurfacingLoop.suggest(
            for: context,
            at: context.observedAt.addingTimeInterval(1)
        )
        guard repeated.isEmpty else { exit(EXIT_FAILURE) }
        _ = try await resurfacingLoop.recordFeedback(
            .later,
            intentionID: linked.id,
            application: application,
            at: context.observedAt.addingTimeInterval(2)
        )
        _ = try await resurfacingLoop.recordFeedback(
            .never,
            intentionID: never.id,
            application: application,
            at: context.observedAt.addingTimeInterval(3)
        )

        let reopened = try EncryptedThoughtRepository(
            directory: directory,
            keyProvider: keyProvider
        )
        let events = try await reopened.suggestionEvents()
        let policy = ResurfacingPolicy()
        guard events.contains(where: { $0.intentionID == linked.id && $0.kind == .later }),
              events.contains(where: { $0.intentionID == never.id && $0.kind == .never }),
              policy.isEligible(
                  rule: linkedRule,
                  events: events,
                  at: context.observedAt.addingTimeInterval(60)
              ) == false,
              policy.isEligible(
                  rule: neverRule,
                  events: events,
                  at: .distantFuture
              ) == false else {
            exit(EXIT_FAILURE)
        }
        print("resurfacing-test=passed")
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }

    private static func focusDiagnosticPacket() throws -> ReturnPacket {
        try ReturnPacket(
            capturedAt: Date(timeIntervalSince1970: 1_723_600_073),
            justCompleted: "packaged completed recovery marker",
            nextAction: "packaged exact next recovery marker",
            blocker: "packaged blocker recovery marker",
            references: [
                "file:///packaged-reference-recovery-marker.md",
                "https://example.test/packaged-recovery-marker",
            ]
        )
    }

    @objc private func showCapture() { quickCapture?.show() }
    @objc private func toggleVoiceCapture() { voiceCapture?.toggle() }
    @objc private func showNow() { presentWorkspace(tab: 0) }
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

    private func presentWorkspace(tab: Int) {
        Task { [weak self] in
            guard let self else { return }
            await contextProvider?.snapshot()
            let application = await contextProvider?.currentContext()
            await model?.refreshContext(application)
            mainWindow?.show(tab: tab)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        workspaceLifecycle?.restoreWorkspace(hasVisibleWindows: flag) ?? false
    }

    private func configureMenu(
        quickCapture: QuickCaptureController,
        mainWindow: MainWindowController
    ) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "OpenLoop")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Capture", action: #selector(showCapture), keyEquivalent: "")
        let voiceItem = menu.addItem(
            withTitle: "Record & Transcribe",
            action: #selector(toggleVoiceCapture),
            keyEquivalent: "r"
        )
        voiceItem.keyEquivalentModifierMask = [.command, .shift]
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
            title: "Private Mode — no background sensing",
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
        application.setActivationPolicy(.regular)
        application.run()
        _ = delegate
    }
}
