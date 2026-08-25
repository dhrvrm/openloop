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

private struct DiagnosticRecallSource: RecallDocumentProviding {
    let values: [RecallDocument]
    func documents() async throws -> [RecallDocument] { values }
}

private actor DiagnosticRecallIndexStore: RecallIndexStore {
    private var value: RecallIndexSnapshot?
    func load() async throws -> RecallIndexSnapshot? { value }
    func save(_ snapshot: RecallIndexSnapshot) async throws { value = snapshot }
    func discard() async throws { value = nil }
}

private struct DiagnosticRecallEmbeddingProvider: EmbeddingProvider {
    let values: [String: [Double]]
    var identifier: String { get async { "recall-fixture-v1" } }
    func vectors(for texts: [String]) async throws -> [[Double]] {
        try texts.map { text in
            guard let vector = values[text] else { throw RecallError.embeddingUnavailable }
            return vector
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var quickCapture: QuickCaptureController?
    private var mainWindow: MainWindowController?
    private var hotKey: GlobalHotKey?
    private var voiceHotKey: GlobalHotKey?
    private var recallHotKey: GlobalHotKey?
    private var meetingRecordHotKey: GlobalHotKey?
    private var voiceCaptureWindow: VoiceCaptureWindowController?
    private var model: AppModel?
    private var pauseMenuItem: NSMenuItem?
    private var privateModeMenuItem: NSMenuItem?
    private var contextProvider: FrontmostApplicationReferenceProvider?
    private var applicationContextObserver: ApplicationContextObserver?
    private var workspaceLifecycle: WorkspaceLifecycle?
    private let launchRecovery = LaunchRecoveryTracker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await start() }
    }

    private func start() async {
        do {
            let recoveredAfterUnexpectedExit = launchRecovery.beginLaunch()
            let directory = dataDirectory()
            let service = ProcessInfo.processInfo.environment["OPENLOOP_KEYCHAIN_SERVICE"]
                ?? "dev.openloop.adhd.vault"
            let keychainProvider = KeychainVaultKeyProvider(service: service)
            let localKeyURL = directory.appendingPathComponent("root-key.local")
            let keyProvider: any VaultKeyProvider
            if Bundle.main.object(forInfoDictionaryKey: "OpenLoopLocalDevelopmentBuild") as? Bool
                == true {
                let vaultURL = directory.appendingPathComponent("openloop.vault")
                guard FileManager.default.fileExists(atPath: localKeyURL.path)
                        || !FileManager.default.fileExists(atPath: vaultURL.path) else {
                    throw VaultKeyError.legacyVaultRequiresExplicitMigration
                }
                keyProvider = LocalFileVaultKeyProvider(fileURL: localKeyURL)
            } else {
                keyProvider = MigratingLocalVaultKeyProvider(
                    fileURL: localKeyURL,
                    fallback: keychainProvider
                )
            }
            let rootKeyData = try keyProvider.loadOrCreateKey()
            let repository = try EncryptedThoughtRepository(
                directory: directory,
                keyData: rootKeyData
            )
            let loop = ThoughtLoop(repository: repository, clarifier: RuleClarificationProvider())
            let contextProvider = FrontmostApplicationReferenceProvider()
            let contextTrailLoop = ContextTrailLoop(repository: repository)
            let focusLoop = FocusLoop(
                repository: repository,
                composer: InterruptionSnapshotComposer(
                    contextProvider: CompositeContextReferenceProvider([
                        contextProvider,
                        ContextTrailReferenceProvider(repository: repository),
                    ])
                )
            )
            let resurfacingLoop = ResurfacingLoop(repository: repository)
            let recallSource = RecallDocumentSource(repository: repository)
            let recallIndex = try EncryptedRecallIndexStore(
                directory: directory,
                rootKeyData: rootKeyData
            )
            let embeddingProvider = NaturalLanguageEmbeddingProvider()
            let recallLoop = RecallLoop(
                source: recallSource,
                indexStore: recallIndex,
                embeddingProvider: embeddingProvider
            )
            let workingMemory = WorkingMemoryCompiler(
                source: recallSource,
                provider: DeterministicMemoryExtractionProvider(),
                repository: repository
            )
            let model = AppModel(
                loop: loop,
                readModels: ThoughtReadModels(repository: repository),
                focusLoop: focusLoop,
                resurfacingLoop: resurfacingLoop,
                recallSearch: recallLoop,
                workingMemory: workingMemory,
                contextTrail: contextTrailLoop,
                privacyManager: LocalPrivacyManager(
                    repository: repository,
                    recallIndex: recallIndex,
                    managedDirectories: [
                        directory.appendingPathComponent("Meeting Staging", isDirectory: true),
                        directory.appendingPathComponent("Models", isDirectory: true),
                    ]
                ),
                semanticGraph: SemanticGraphLoop(
                    repository: repository,
                    embeddingProvider: embeddingProvider
                )
            )
            model.recoveryNotice = recoveredAfterUnexpectedExit
                ? "OpenLoop recovered your saved work after an unexpected exit."
                : nil
            model.capabilitySummary = .current()
            let mcpRuntime = MCPRuntime(
                configurationURL: directory.appendingPathComponent("MCP/servers.json")
            )
            let capabilityRegistry = CapabilityRegistry(repository: repository)
            _ = try await capabilityRegistry.discover([])
            model.attachCapabilityRuntime(
                registry: capabilityRegistry,
                repository: repository,
                invoker: mcpRuntime
            )
            Task { [weak model] in
                let capabilities = await mcpRuntime.discoverCapabilities()
                _ = try? await capabilityRegistry.discover(capabilities)
                await model?.refreshCapabilityRuntime()
            }
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
            let whisperTranscriber = WhisperKitMeetingTranscriber(
                modelStorageURL: directory.appendingPathComponent("Models/WhisperKit", isDirectory: true)
            )
            let voiceLearning = VoiceLearningLoop(repository: repository)
            let textEditor = QwenLocalTextEditor { [weak model] message in
                Task { @MainActor in
                    guard model?.isDeliveringDictation == true else { return }
                    model?.dictationProcessingMessage = message
                }
            }
            let dictationCoordinator = VoiceDictationCoordinator(
                processor: LocalSpeechProcessor(
                    compactEditor: textEditor,
                    largeEditor: textEditor,
                    normalizationRules: {
                        (try? await voiceLearning.normalizationRules()) ?? []
                    }
                ),
                contextEngine: VoiceContextEngine(
                    reader: AccessibilityVoiceContextReader(),
                    isConsented: { [weak model] in model?.isVoiceContextEnabled ?? false }
                ),
                output: TextOutputAdapter(
                    accessibility: SystemAccessibilityTextInserter(),
                    clipboard: RestoringClipboardPaster(),
                    keyboard: SystemKeyboardTyper()
                )
            )
            model.attachVoiceDictation(dictationCoordinator)
            let qualityQwenTranscriber = QwenMeetingTranscriber(
                modelStorageURL: directory.appendingPathComponent(
                    "Models/Qwen3-ASR-1.7B-8bit",
                    isDirectory: true
                ),
                fallback: whisperTranscriber,
                fallbackEnabled: false,
                contextProvider: {
                    (try? await voiceLearning.vocabulary(limit: 80)) ?? []
                }
            )
            let streamingQwenTranscriber = QwenMeetingTranscriber(
                qwenModelID: QwenMeetingTranscriber.streamingModelID,
                modelStorageURL: directory.appendingPathComponent(
                    "Models/Qwen3-ASR",
                    isDirectory: true
                ),
                fallback: whisperTranscriber,
                fallbackEnabled: false,
                contextProvider: {
                    (try? await voiceLearning.vocabulary(limit: 80)) ?? []
                }
            )
            let meetingTranscriber = AccuracyFirstTranscriber(
                primary: whisperTranscriber,
                witness: qualityQwenTranscriber,
                expectedDomainTerms: {
                    (try? await voiceLearning.vocabulary(limit: 80)) ?? []
                }
            )
            let dictationTranscriber = AccuracyFirstTranscriber(
                primary: qualityQwenTranscriber,
                witness: whisperTranscriber,
                expectedDomainTerms: {
                    (try? await voiceLearning.vocabulary(limit: 80)) ?? []
                }
            )
            model.attachVoiceQualityAudit(
                VoiceQualityCorpusAuditor(repository: repository),
                engineIdentifier: qualityQwenTranscriber.modelIdentifier
            )
            let meetingIntelligence = LocalMeetingIntelligenceProvider()
            let meetingController = MeetingTranscriptionController(
                repository: repository,
                transcriber: meetingTranscriber,
                dictationTranscriber: dictationTranscriber,
                stagingDirectory: directory.appendingPathComponent("Meeting Staging", isDirectory: true),
                recorder: MeetingAudioRecorder(),
                streamingBuilder: LocalStreamingVoiceSessionBuilder(
                    recognizer: streamingQwenTranscriber,
                    vadStorageURL: directory.appendingPathComponent("Models/Silero-VAD", isDirectory: true),
                    context: {
                        (try? await voiceLearning.vocabulary(limit: 80)) ?? []
                    }
                ),
                intelligenceProvider: meetingIntelligence,
                titleProvider: meetingIntelligence
            )
            model.attachMeetingTranscription(meetingController)
            let mainWindow = MainWindowController(model: model)
            let voiceCaptureWindow = VoiceCaptureWindowController(model: model)
            self.quickCapture = quickCapture
            self.mainWindow = mainWindow
            self.voiceCaptureWindow = voiceCaptureWindow
            self.model = model
            self.contextProvider = contextProvider
            let applicationContextObserver = ApplicationContextObserver { [weak model] application in
                Task { await model?.observeApplication(application) }
            }
            applicationContextObserver.start()
            self.applicationContextObserver = applicationContextObserver
            let workspaceLifecycle = WorkspaceLifecycle { [weak self] tab in
                self?.presentWorkspace(tab: tab)
            }
            self.workspaceLifecycle = workspaceLifecycle
            configureMenu(quickCapture: quickCapture, mainWindow: mainWindow)
            await contextProvider.snapshot()
            await model.refreshContext(await contextProvider.currentContext())
            await model.refreshContextTrail()
            mainWindow.show(tab: 0)
            do {
                hotKey = try GlobalHotKey { [weak quickCapture, weak model] startedAt in
                    model?.showShortcutFeedback(ShortcutFeedback(
                        kind: .capture,
                        title: "Quick Capture opened",
                        shortcut: "⌘⇧Space"
                    ))
                    quickCapture?.show(startedAt: startedAt)
                }
                model.capabilitySummary.quickCapture = .ready
            } catch {
                model.capabilitySummary.quickCapture = .unavailable
                model.commandError = "Quick Capture shortcut is unavailable. Use Capture in the menu."
            }
            do {
                let binding = GlobalHotKeyBinding.voiceCapture
                voiceHotKey = try GlobalHotKey(
                    keyCode: binding.keyCode,
                    modifiers: binding.modifiers,
                    id: binding.id
                ) { [weak model] _ in
                    model?.showShortcutFeedback(ShortcutFeedback(
                        kind: .dictation,
                        title: model?.isSystemDictationActive == true
                            ? "Finishing dictation"
                            : "Dictation started",
                        shortcut: "⌃⌥Space"
                    ))
                    model?.toggleSystemDictation()
                }
            } catch {
                model.resurfacingError = "Voice shortcut is unavailable. Use Dictate & Insert in the menu."
            }
            do {
                let binding = GlobalHotKeyBinding.recall
                recallHotKey = try GlobalHotKey(
                    keyCode: binding.keyCode,
                    modifiers: binding.modifiers,
                    id: binding.id
                ) { [weak self] _ in
                    self?.model?.showShortcutFeedback(ShortcutFeedback(
                        kind: .search,
                        title: "Ask opened",
                        shortcut: "⌘⇧F"
                    ))
                    self?.mainWindow?.show(tab: 3)
                }
            } catch {
                model.recallError = "Ask shortcut is unavailable. Use Ask in the menu."
            }
            do {
                let binding = GlobalHotKeyBinding.meetingRecord
                meetingRecordHotKey = try GlobalHotKey(
                    keyCode: binding.keyCode,
                    modifiers: binding.modifiers,
                    id: binding.id
                ) { [weak model] _ in
                    model?.showShortcutFeedback(ShortcutFeedback(
                        kind: .recording,
                        title: model?.meetingJob.stage == .recording
                            ? "Finishing recording"
                            : "Recording started",
                        shortcut: "⌃⌥R"
                    ))
                    model?.toggleVoiceCapture()
                }
            } catch {
                model.commandError = "Record shortcut is unavailable. Use Record in the capture bar."
            }
        } catch {
            NSApp.presentError(error)
        }
    }

    private func runDiagnosticIfRequested(
        directory: URL,
        keyProvider: any VaultKeyProvider,
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
            let voiceBinding = GlobalHotKeyBinding.voiceCapture
            let voiceHotKey = try GlobalHotKey(
                keyCode: voiceBinding.keyCode,
                modifiers: voiceBinding.modifiers,
                id: voiceBinding.id
            ) { _ in }
            let recallBinding = GlobalHotKeyBinding.recall
            let recallHotKey = try GlobalHotKey(
                keyCode: recallBinding.keyCode,
                modifiers: recallBinding.modifiers,
                id: recallBinding.id
            ) { _ in }
            let recordBinding = GlobalHotKeyBinding.meetingRecord
            let recordHotKey = try GlobalHotKey(
                keyCode: recordBinding.keyCode,
                modifiers: recordBinding.modifiers,
                id: recordBinding.id
            ) { _ in }
            withExtendedLifetime((captureHotKey, voiceHotKey, recallHotKey, recordHotKey)) {
                print("hotkey-registration=passed")
                print("voice-hotkey-registration=passed")
                print("recall-hotkey-registration=passed")
                print("record-hotkey-registration=passed")
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

        case "--voice-benchmark":
            guard arguments.count > 1 else {
                print("voice-benchmark-error=missing-fixture")
                exit(EXIT_FAILURE)
            }
            do {
                let fixtureURL = URL(fileURLWithPath: arguments[1])
                let data = try Data(contentsOf: fixtureURL)
                let samples = try JSONDecoder().decode([VoiceBenchmarkSample].self, from: data)
                let report = VoiceBenchmarkReport(samples: samples)
                print("voice-benchmark-samples=\(report.sampleCount)")
                print("voice-benchmark-wer=\(Self.metricText(report.wordErrorRate))")
                print("voice-benchmark-first-partial-p95-ms=\(Self.metricText(report.firstPartialP95Milliseconds))")
                print("voice-benchmark-final-p95-ms=\(Self.metricText(report.finalP95Milliseconds))")
                for category in VoiceBenchmarkCategory.allCases {
                    print("voice-benchmark-\(category.rawValue)-wer=\(Self.metricText(report.wordErrorRate(for: category)))")
                }
                return true
            } catch {
                print("voice-benchmark-error=malformed-fixture")
                exit(EXIT_FAILURE)
            }

        case "--recall-evaluation":
            guard arguments.count > 1 else {
                print("recall-fixture-error=missing-fixture")
                exit(EXIT_FAILURE)
            }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let fixture = try decoder.decode(
                    RecallEvaluationFixture.self,
                    from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
                )
                let recall = RecallLoop(
                    source: DiagnosticRecallSource(values: fixture.documents),
                    indexStore: DiagnosticRecallIndexStore(),
                    embeddingProvider: DiagnosticRecallEmbeddingProvider(values: fixture.vectors)
                )
                var results: [RecallResult] = []
                var latencies: [Double] = []
                for evaluation in fixture.cases {
                    let started = ContinuousClock.now
                    results.append(try await recall.retrieve(RecallQuery(text: evaluation.query)))
                    latencies.append(Self.milliseconds(since: started))
                }
                let report = RecallEvaluationReport(
                    cases: fixture.cases,
                    results: results,
                    latenciesMilliseconds: latencies
                )
                print("recall-fixture-cases=\(report.caseCount)")
                print("recall-fixture-top-five-hit-rate=\(Self.metricText(report.topFiveHitRate))")
                print("recall-fixture-exact-p95-ms=\(Self.metricText(report.exactSearchP95Milliseconds))")
                return true
            } catch {
                print("recall-fixture-error=malformed-fixture")
                exit(EXIT_FAILURE)
            }

        case "--memory-evaluation":
            guard arguments.count > 1 else {
                print("memory-fixture-error=missing-fixture")
                exit(EXIT_FAILURE)
            }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let fixture = try decoder.decode(
                    MemoryEvaluationFixture.self,
                    from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
                )
                let report = try await MemoryFixtureEvaluator().evaluate(fixture)
                print("memory-fixture-accepted=\(report.acceptedMemoryCount)")
                print("memory-fixture-evidence-coverage=\(Self.metricText(report.evidenceCoverage))")
                print("memory-fixture-contradiction-preservation=\(Self.metricText(report.contradictionPreservation))")
                print("memory-fixture-current-state-accuracy=\(Self.metricText(report.currentStateAccuracy))")
                return true
            } catch {
                print("memory-fixture-error=malformed-fixture")
                exit(EXIT_FAILURE)
            }

        case "--context-trail-evaluation":
            guard arguments.count > 1 else {
                print("context-trail-fixture-error=missing-fixture")
                exit(EXIT_FAILURE)
            }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let fixture = try decoder.decode(
                    ContextTrailEvaluationFixture.self,
                    from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
                )
                let report = try ContextTrailFixtureEvaluator().evaluate(fixture)
                print("context-trail-fixture-accepted=\(report.acceptedEventCount)")
                print("context-trail-fixture-compression-ratio=\(Self.metricText(report.episodeCompressionRatio))")
                print("context-trail-fixture-false-event-rate=\(Self.metricText(report.falseEventRate))")
                print("context-trail-fixture-return-coverage=\(Self.metricText(report.returnReferenceCoverage))")
                return true
            } catch {
                print("context-trail-fixture-error=malformed-fixture")
                exit(EXIT_FAILURE)
            }

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

    private static func metricText(_ value: Double?) -> String {
        guard let value else { return "empty" }
        return String(
            format: "%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    private func runResurfacingDiagnostic(
        directory: URL,
        keyProvider: any VaultKeyProvider,
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
    @objc private func toggleVoiceCapture() { model?.toggleSystemDictation() }
    @objc private func showLive() { presentWorkspace(tab: 0) }
    @objc private func showContext() { mainWindow?.show(tab: 1) }
    @objc private func showEmerging() { mainWindow?.show(tab: 2) }
    @objc private func showAsk() { mainWindow?.show(tab: 3) }
    @objc private func showAct() { mainWindow?.show(tab: 4) }
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
    @objc private func toggleContextTrail() {
        guard let model else { return }
        Task { await model.setContextTrailEnabled(!model.contextTrailSettings.isEnabled) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        applicationContextObserver?.stop()
        launchRecovery.markCleanExit()
    }

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
            withTitle: "Dictate & Insert",
            action: #selector(toggleVoiceCapture),
            keyEquivalent: " "
        )
        voiceItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(withTitle: "Now", action: #selector(showLive), keyEquivalent: "")
        let pauseItem = menu.addItem(
            withTitle: "Pause",
            action: #selector(pauseOrContinue),
            keyEquivalent: ""
        )
        pauseItem.isEnabled = false
        pauseMenuItem = pauseItem
        menu.addItem(withTitle: "Context", action: #selector(showContext), keyEquivalent: "")
        menu.addItem(withTitle: "Emerging", action: #selector(showEmerging), keyEquivalent: "")
        let recallItem = menu.addItem(
            withTitle: "Ask",
            action: #selector(showAsk),
            keyEquivalent: "f"
        )
        recallItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(withTitle: "Act", action: #selector(showAct), keyEquivalent: "")
        menu.addItem(.separator())
        let privateMode = NSMenuItem(
            title: ContextTrailMenuPresentation.title(for: .privateMode),
            action: #selector(toggleContextTrail),
            keyEquivalent: ""
        )
        privateMode.state = .on
        privateModeMenuItem = privateMode
        menu.addItem(privateMode)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit OpenLoop", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let model, let privateModeMenuItem {
            privateModeMenuItem.title = ContextTrailMenuPresentation.title(
                for: model.contextTrailSettings.mode
            )
            privateModeMenuItem.isEnabled = !model.isUpdatingContextTrail
        }
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

enum ContextTrailMenuPresentation {
    static func title(for mode: ContextCollectionMode) -> String {
        switch mode {
        case .privateMode: "Private Mode — on"
        case .focusTrail: "Focus Context — on"
        }
    }
}

@main
struct OpenLoopApplication {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if VoiceEvaluationCommand.isRequested(arguments) {
            do {
                VoiceEvaluationCommandExecutor.execute(
                    try VoiceEvaluationCommand(arguments: arguments)
                )
            } catch {
                FileHandle.standardError.write(Data("voice-eval-error: \(error)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
        _ = delegate
    }
}
