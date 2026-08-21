import ADHDCore
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var captureError: String?
    @Published var commandError: String?
    @Published var isSaving = false
    @Published var now: NowItem?
    @Published var returns: [ReturnItem] = []
    @Published var later: [LaterItem] = []
    @Published var openLoops: [OpenLoopItem] = []
    @Published var reviewItems: [ClarificationReviewItem] = []
    @Published var reviewError: String?
    @Published var isSavingReview = false
    @Published var currentApplication: ApplicationContext?
    @Published var suggestions: [ContextualSuggestion] = []
    @Published var resurfacingRules: [ResurfacingRule] = []
    @Published var resurfacingError: String?
    @Published var recallQuery = ""
    @Published var recallHits: [RecallHit] = []
    @Published var isRecalling = false
    @Published var recallError: String?
    @Published var memoryRecords: [MemoryRecord] = []
    @Published var isCompilingMemory = false
    @Published var memoryError: String?
    @Published var contextTrailSettings = ContextTrailSettings()
    @Published var contextEpisodes: [ContextEpisode] = []
    @Published var isUpdatingContextTrail = false
    @Published var contextTrailError: String?
    @Published var privacySummary = PrivacyDataSummary.empty
    @Published var retentionPolicy = PrivacyRetentionPolicy.keepForever
    @Published var isUpdatingPrivacy = false
    @Published var privacyError: String?
    @Published var privacyNotice: String?
    @Published var recoveryNotice: String?
    @Published var capabilitySummary = CapabilitySummary()
    @Published var voiceCapture = VoiceCapturePresentation()
    @Published var meetingJob = MeetingJobPresentation()
    @Published var meetingTranscripts: [MeetingTranscript] = []
    @Published var meetingEngineDiagnostics = MeetingEngineDiagnostics.checking
    @Published var meetingPipelineEvents: [MeetingPipelineEvent] = []
    @Published var recordingDecibels: Float?
    @Published var streamingVoiceSession: VoiceSessionSnapshot?
    @Published var isAdvancedModeEnabled: Bool
    @Published var meetingLanguagePreference: MeetingLanguagePreference
    @Published var semanticNodes: [SemanticNode] = []
    @Published var semanticRelations: [SemanticRelation] = []
    @Published var semanticVectors: [UUID: SemanticVector] = [:]
    @Published var emergingThreads: [SemanticThread] = []
    @Published var unresolvedSemanticNodes: [SemanticNode] = []
    @Published var semanticQuery = ""
    @Published var semanticAnswers: [SemanticNode] = []
    @Published var isRefreshingSemanticGraph = false
    @Published var semanticError: String?
    @Published var voiceQualityAudit: VoiceQualityCorpusAudit?
    @Published var voiceQualityAuditError: String?
    @Published var voiceMode: VoiceMode
    @Published var lastDictationDelivery: VoiceDictationDelivery?
    @Published var isDeliveringDictation = false
    @Published var dictationProcessingMessage: String?
    @Published var dictationActionNotice: String?
    @Published var isVoiceContextEnabled: Bool
    @Published private(set) var isSystemDictationActive = false

    private let loop: ThoughtLoop
    private let readModels: ThoughtReadModels
    private let focusLoop: FocusLoop?
    private let resurfacingLoop: ResurfacingLoop?
    private let recallSearch: (any RecallSearching)?
    private let workingMemory: (any WorkingMemoryCompiling)?
    private let contextTrail: (any ContextTrailProviding)?
    private let privacyManager: (any PrivacyManaging)?
    private let semanticGraph: SemanticGraphLoop?
    private var voiceQualityAuditor: (any VoiceQualityAuditing)?
    private var voiceQualityEngineIdentifier: String?
    private let defaults: UserDefaults
    private let advancedModeKey: String
    private let voiceModeKey: String
    private let voiceContextKey: String
    private var recallGeneration = 0
    private var voiceController: VoiceTranscriptionController?
    private var voiceObservation: AnyCancellable?
    private var meetingController: MeetingTranscriptionController?
    private var meetingJobObservation: AnyCancellable?
    private var meetingTranscriptObservation: AnyCancellable?
    private var meetingDiagnosticsObservation: AnyCancellable?
    private var meetingEventsObservation: AnyCancellable?
    private var meetingMeterObservation: AnyCancellable?
    private var meetingStreamingObservation: AnyCancellable?
    private var dictationCoordinator: (any VoiceDictationCoordinating)?
    private var deliveredTranscriptID: UUID?

    init(
        loop: ThoughtLoop,
        readModels: ThoughtReadModels,
        focusLoop: FocusLoop? = nil,
        resurfacingLoop: ResurfacingLoop? = nil,
        recallSearch: (any RecallSearching)? = nil,
        workingMemory: (any WorkingMemoryCompiling)? = nil,
        contextTrail: (any ContextTrailProviding)? = nil,
        privacyManager: (any PrivacyManaging)? = nil,
        semanticGraph: SemanticGraphLoop? = nil,
        defaults: UserDefaults = .standard,
        advancedModeKey: String = "OpenLoopAdvancedMode",
        voiceModeKey: String = "OpenLoopVoiceMode",
        voiceContextKey: String = "OpenLoopVoiceContextEnabled"
    ) {
        self.loop = loop
        self.readModels = readModels
        self.focusLoop = focusLoop
        self.resurfacingLoop = resurfacingLoop
        self.recallSearch = recallSearch
        self.workingMemory = workingMemory
        self.contextTrail = contextTrail
        self.privacyManager = privacyManager
        self.semanticGraph = semanticGraph
        self.defaults = defaults
        self.advancedModeKey = advancedModeKey
        self.voiceModeKey = voiceModeKey
        self.voiceContextKey = voiceContextKey
        isAdvancedModeEnabled = defaults.bool(forKey: advancedModeKey)
        meetingLanguagePreference = .automatic
        voiceMode = defaults.string(forKey: voiceModeKey)
            .flatMap(VoiceMode.init(rawValue:)) ?? .polished
        isVoiceContextEnabled = defaults.object(forKey: voiceContextKey) == nil
            ? true
            : defaults.bool(forKey: voiceContextKey)
    }

    func attachVoiceCapture(_ controller: VoiceTranscriptionController) {
        voiceController = controller
        voiceObservation = Publishers.CombineLatest4(
            controller.$state,
            controller.$statusMessage,
            controller.$startedAt,
            controller.$transcript
        ).sink { [weak self] state, message, startedAt, transcript in
            self?.voiceCapture = VoiceCapturePresentation(
                state: state,
                statusMessage: message,
                startedAt: startedAt,
                transcript: transcript
            )
        }
    }

    func toggleVoiceCapture() {
        if let meetingController {
            Task { await meetingController.toggleRecording() }
            return
        }
        guard let voiceController else {
            commandError = "Voice capture is unavailable."
            return
        }
        Task { await voiceController.toggle() }
    }

    func attachVoiceDictation(_ coordinator: any VoiceDictationCoordinating) {
        dictationCoordinator = coordinator
    }

    func toggleSystemDictation() {
        guard let meetingController else {
            commandError = "Local dictation is unavailable."
            return
        }
        if meetingJob.stage == .recording {
            if isSystemDictationActive {
                Task { await meetingController.toggleRecording() }
            } else {
                commandError = "A meeting recording is already active. Stop it from Now before dictating."
            }
            return
        }
        guard !meetingJob.isActive else {
            commandError = "Wait for the current local transcription to finish."
            return
        }
        guard dictationCoordinator != nil else {
            commandError = "System-wide text output is unavailable."
            return
        }
        isSystemDictationActive = true
        deliveredTranscriptID = nil
        lastDictationDelivery = nil
        dictationActionNotice = nil
        dictationProcessingMessage = "Listening for system-wide dictation"
        commandError = nil
        Task { await meetingController.toggleRecording() }
    }

    func cancelVoiceCapture() {
        isSystemDictationActive = false
        isDeliveringDictation = false
        if meetingController != nil {
            meetingController?.cancel()
        } else {
            voiceController?.cancel()
        }
    }

    func attachMeetingTranscription(_ controller: MeetingTranscriptionController) {
        meetingController = controller
        controller.setLanguagePreference(meetingLanguagePreference)
        meetingJobObservation = controller.$job.sink { [weak self] job in
            guard let self else { return }
            meetingJob = job
            handleDictationJob(job)
        }
        meetingTranscriptObservation = controller.$transcripts.sink { [weak self] in
            self?.meetingTranscripts = $0
        }
        meetingDiagnosticsObservation = controller.$engineDiagnostics.sink { [weak self] in
            self?.meetingEngineDiagnostics = $0
        }
        meetingEventsObservation = controller.$pipelineEvents.sink { [weak self] in
            self?.meetingPipelineEvents = $0
        }
        meetingMeterObservation = controller.$recordingDecibels.sink { [weak self] in
            self?.recordingDecibels = $0
        }
        meetingStreamingObservation = controller.$streamingSnapshot.sink { [weak self] in
            self?.streamingVoiceSession = $0
        }
        Task { await controller.refresh() }
    }

    func attachVoiceQualityAudit(
        _ auditor: any VoiceQualityAuditing,
        engineIdentifier: String
    ) {
        voiceQualityAuditor = auditor
        voiceQualityEngineIdentifier = engineIdentifier
        Task { await refreshVoiceQualityAudit() }
    }

    func refreshVoiceQualityAudit() async {
        guard let voiceQualityAuditor, let voiceQualityEngineIdentifier else { return }
        do {
            voiceQualityAudit = try await voiceQualityAuditor.audit(
                engineIdentifier: voiceQualityEngineIdentifier
            )
            voiceQualityAuditError = nil
        } catch {
            voiceQualityAuditError = "Quality evidence could not be audited. No release claim was enabled."
        }
    }

    func setAdvancedModeEnabled(_ enabled: Bool) {
        isAdvancedModeEnabled = enabled
        defaults.set(enabled, forKey: advancedModeKey)
    }

    func setVoiceMode(_ mode: VoiceMode) {
        voiceMode = mode
        defaults.set(mode.rawValue, forKey: voiceModeKey)
    }

    func setVoiceContextEnabled(_ enabled: Bool) {
        isVoiceContextEnabled = enabled
        defaults.set(enabled, forKey: voiceContextKey)
    }

    func confirmPendingVoiceCommand() {
        guard let delivery = dictationCoordinator?.confirmPendingCommand() else { return }
        lastDictationDelivery = delivery
        dictationActionNotice = delivery.statusMessage
        commandError = delivery.state == .failed ? delivery.statusMessage : nil
    }

    func discardPendingVoiceCommand() {
        dictationCoordinator?.discardPendingCommand()
        lastDictationDelivery = nil
        dictationActionNotice = "Voice command cancelled."
    }

    func dismissDictationStatus() {
        lastDictationDelivery = nil
        dictationActionNotice = nil
        dictationProcessingMessage = nil
        commandError = nil
    }

    func undoLastDictationOutput() {
        guard let result = dictationCoordinator?.undoLastOutput() else { return }
        if result.inserted {
            lastDictationDelivery = nil
            dictationActionNotice = "Undid the last output in the active app."
            commandError = nil
        } else {
            dictationActionNotice = "Undo needs Accessibility access and an active editable field."
            commandError = dictationActionNotice
        }
    }

    private func handleDictationJob(_ job: MeetingJobPresentation) {
        guard isSystemDictationActive else { return }
        if job.stage == .failed || job.stage == .cancelled {
            isSystemDictationActive = false
            isDeliveringDictation = false
            commandError = job.message
            dictationActionNotice = job.message
            return
        }
        guard job.stage == .ready,
              let transcriptID = job.completedTranscriptID,
              deliveredTranscriptID != transcriptID,
              let text = job.previewText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let dictationCoordinator
        else { return }
        deliveredTranscriptID = transcriptID
        isSystemDictationActive = false
        isDeliveringDictation = true
        dictationProcessingMessage = "Processing transcript locally"
        let mode = voiceMode
        Task { [weak self] in
            let delivery = await dictationCoordinator.deliver(rawText: text, mode: mode)
            guard let self else { return }
            lastDictationDelivery = delivery
            dictationActionNotice = nil
            isDeliveringDictation = false
            dictationProcessingMessage = delivery.statusMessage
            commandError = delivery.state == .failed ? delivery.statusMessage : nil
        }
    }

    func setMeetingLanguagePreference(_ preference: MeetingLanguagePreference) {
        guard !meetingJob.isActive else { return }
        meetingLanguagePreference = preference
        meetingController?.setLanguagePreference(preference)
    }

    func importMeetingAudio(_ url: URL) {
        guard let meetingController else {
            commandError = "Local meeting transcription is unavailable."
            return
        }
        meetingController.importAudio(url)
    }

    func retryMeetingTranscription() { meetingController?.retry() }
    func cancelMeetingTranscription() { meetingController?.cancel() }
    func clearMeetingJob() { meetingController?.clearFinishedJob() }

    func deleteMeetingTranscript(_ id: UUID) async {
        await meetingController?.deleteTranscript(id: id)
    }

    @discardableResult
    func correctMeetingSegment(
        transcriptID: UUID,
        segmentID: UUID,
        correctedText: String,
        scope: VocabularyScope = .personal
    ) async -> Bool {
        guard let meetingController else { return false }
        let saved = await meetingController.correctSegment(
            transcriptID: transcriptID,
            segmentID: segmentID,
            correctedText: correctedText,
            scope: scope
        )
        if !saved {
            commandError = "That correction could not be saved. The original transcript is unchanged."
        }
        return saved
    }

    @discardableResult
    func captureMeetingTranscript(_ id: UUID) async -> Bool {
        guard let transcript = meetingTranscripts.first(where: { $0.id == id }) else {
            return false
        }
        return await submitCapture(transcript.text)
    }

    func refreshContextTrail(at date: Date = .now) async {
        guard let contextTrail else { return }
        do {
            let settings = try await contextTrail.settings()
            let episodes = try await contextTrail.currentEpisodes(at: date)
            contextTrailSettings = settings
            contextEpisodes = episodes
            contextTrailError = nil
        } catch {
            contextTrailError = "Context trail paused. Focus and capture remain safe."
        }
    }

    func setContextTrailEnabled(_ enabled: Bool, at date: Date = .now) async {
        guard !isUpdatingContextTrail, let contextTrail else { return }
        isUpdatingContextTrail = true
        contextTrailError = nil
        defer { isUpdatingContextTrail = false }
        do {
            contextTrailSettings = try await contextTrail.setEnabled(enabled)
            if enabled, let currentApplication {
                _ = try await contextTrail.observe(currentApplication, at: date)
            }
            contextEpisodes = try await contextTrail.currentEpisodes(at: date)
        } catch {
            contextTrailError = "Privacy preference could not be saved. No new context was accepted."
        }
    }

    func observeApplication(_ application: ApplicationContext, at date: Date = .now) async {
        currentApplication = application
        guard let contextTrail else { return }
        do {
            _ = try await contextTrail.observe(application, at: date)
            contextTrailSettings = try await contextTrail.settings()
            contextEpisodes = try await contextTrail.currentEpisodes(at: date)
            contextTrailError = nil
        } catch {
            contextTrailError = "Context trail paused. Focus and capture remain safe."
        }
    }

    func refreshMemory() async {
        guard !isCompilingMemory, let workingMemory else { return }
        isCompilingMemory = true
        memoryError = nil
        defer { isCompilingMemory = false }
        do {
            memoryRecords = try await workingMemory.compile()
        } catch {
            memoryError = "Working memory could not refresh. Existing evidence is unchanged."
            return
        }
        if let semanticGraph {
            do {
                _ = try await semanticGraph.synchronize(memoryRecords: memoryRecords)
                _ = try? await semanticGraph.enrichMissingVectors()
                await refreshSemanticGraph()
            } catch {
                semanticError = "Memory is safe, but its graph projection is waiting to refresh."
            }
        }
    }

    func searchRecall(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        recallGeneration += 1
        let generation = recallGeneration
        recallQuery = query
        recallError = nil
        guard !query.isEmpty else {
            recallHits = []
            isRecalling = false
            return
        }
        guard let recallSearch else {
            recallHits = []
            recallError = "Recall is unavailable in this build."
            return
        }
        isRecalling = true
        do {
            let result = try await recallSearch.retrieve(RecallQuery(text: query))
            guard generation == recallGeneration else { return }
            recallHits = result.hits
            isRecalling = false
        } catch {
            guard generation == recallGeneration else { return }
            recallHits = []
            isRecalling = false
            recallError = "Exact search is still available after reopening Recall."
        }
    }

    func refreshSemanticGraph() async {
        guard let semanticGraph, !isRefreshingSemanticGraph else { return }
        isRefreshingSemanticGraph = true
        defer { isRefreshingSemanticGraph = false }
        do {
            let graph = try await semanticGraph.graph()
            semanticNodes = graph.nodes.values.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            semanticRelations = graph.relations.values.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            semanticVectors = graph.vectors
            emergingThreads = try await semanticGraph.emerging()
            unresolvedSemanticNodes = try await semanticGraph.unresolved()
            semanticError = nil
        } catch {
            semanticError = "Semantic context is temporarily unavailable. Original evidence is unchanged."
        }
    }

    func askSemanticContext(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        semanticQuery = query
        semanticError = nil
        guard !query.isEmpty else {
            semanticAnswers = []
            return
        }
        guard let semanticGraph else {
            semanticAnswers = []
            semanticError = "Semantic context is unavailable in this build."
            return
        }
        do {
            semanticAnswers = try await semanticGraph.ask(query)
        } catch {
            semanticAnswers = []
            semanticError = "Semantic context could not be searched. Original evidence is unchanged."
        }
    }

    func refreshContext(_ application: ApplicationContext?, at date: Date = .now) async {
        guard let resurfacingLoop else { return }
        if application == currentApplication, suggestions.isEmpty == false { return }
        currentApplication = application
        suggestions = []
        resurfacingError = nil
        guard let application else { return }
        do {
            resurfacingRules = try await resurfacingLoop.rules()
            suggestions = try await resurfacingLoop.suggest(
                for: ContextEvent(observedAt: date, application: application),
                at: date
            )
        } catch {
            resurfacingError = "Suggestions are quiet for now. Your stored work is safe."
        }
    }

    func isLinked(_ intentionID: UUID, to application: ApplicationContext) -> Bool {
        resurfacingRules.contains {
            $0.intentionID == intentionID
                && $0.application.bundleIdentifier == application.bundleIdentifier
        }
    }

    @discardableResult
    func linkSuggestion(
        _ intentionID: UUID,
        to application: ApplicationContext,
        at date: Date = .now
    ) async -> Bool {
        guard let resurfacingLoop else { return false }
        resurfacingError = nil
        do {
            _ = try await resurfacingLoop.link(
                intentionID: intentionID,
                to: application,
                at: date
            )
            currentApplication = application
            resurfacingRules = try await resurfacingLoop.rules()
            suggestions = try await resurfacingLoop.suggest(
                for: ContextEvent(observedAt: date, application: application),
                at: date
            )
            return true
        } catch {
            resurfacingError = "That context preference could not be saved. Your open loop is safe."
            return false
        }
    }

    @discardableResult
    func unlinkSuggestion(_ intentionID: UUID) async -> Bool {
        guard let resurfacingLoop else { return false }
        resurfacingError = nil
        do {
            try await resurfacingLoop.unlink(intentionID: intentionID)
            resurfacingRules = try await resurfacingLoop.rules()
            suggestions.removeAll { $0.intentionID == intentionID }
            return true
        } catch {
            resurfacingError = "That context preference could not be saved. Your open loop is safe."
            return false
        }
    }

    @discardableResult
    func startSuggestion(_ intentionID: UUID, at date: Date = .now) async -> Bool {
        guard await startFocus(intentionID),
              let application = currentApplication,
              let resurfacingLoop else {
            return false
        }
        do {
            _ = try await resurfacingLoop.recordFeedback(
                .started,
                intentionID: intentionID,
                application: application,
                at: date
            )
            suggestions.removeAll { $0.intentionID == intentionID }
            return true
        } catch {
            resurfacingError = "Focus started. Its suggestion feedback could not be saved."
            suggestions.removeAll { $0.intentionID == intentionID }
            return true
        }
    }

    func deferSuggestion(_ intentionID: UUID, at date: Date = .now) async -> Bool {
        await applyFeedback(.later, intentionID: intentionID, at: date)
    }

    func silenceSuggestion(_ intentionID: UUID, at date: Date = .now) async -> Bool {
        await applyFeedback(.never, intentionID: intentionID, at: date)
    }

    private func applyFeedback(
        _ feedback: ResurfacingFeedback,
        intentionID: UUID,
        at date: Date
    ) async -> Bool {
        guard let application = currentApplication, let resurfacingLoop else { return false }
        resurfacingError = nil
        do {
            _ = try await resurfacingLoop.recordFeedback(
                feedback,
                intentionID: intentionID,
                application: application,
                at: date
            )
            suggestions.removeAll { $0.intentionID == intentionID }
            return true
        } catch {
            resurfacingError = "That suggestion choice could not be saved. Your open loop is safe."
            return false
        }
    }

    func submitCapture(_ text: String) async -> Bool {
        guard isSaving == false else { return false }
        isSaving = true
        captureError = nil
        do {
            let capture = try await loop.accept(text: text, at: .now)
            isSaving = false
            if let semanticGraph {
                do {
                    let node = try await semanticGraph.recordObservation(capture: capture)
                    await refreshSemanticGraph()
                    Task { [weak self] in
                        guard let self else { return }
                        _ = try? await semanticGraph.enrichVector(
                            nodeID: node.id,
                            text: node.claim
                        )
                        await self.refreshSemanticGraph()
                    }
                } catch {
                    semanticError = "Captured safely, but semantic context is waiting to refresh."
                }
            }
            Task {
                do {
                    _ = try await loop.clarify(capture)
                    await refresh()
                } catch {
                    captureError = "Saved, but clarification is waiting."
                    await refresh()
                }
            }
            return true
        } catch {
            isSaving = false
            captureError = "Could not save. Your text is still here."
            return false
        }
    }

    func recoverPendingClarification() async {
        _ = await loop.recoverUnclarifiedCaptures()
        await refresh()
    }

    @discardableResult
    func applyClarificationReview(
        captureID: UUID,
        disposition: Disposition,
        desiredOutcome: String?,
        nextAction: String?,
        at date: Date = .now
    ) async -> Bool {
        guard isSavingReview == false else { return false }
        isSavingReview = true
        reviewError = nil
        defer { isSavingReview = false }
        do {
            _ = try await loop.review(
                captureID: captureID,
                disposition: disposition,
                desiredOutcome: desiredOutcome,
                nextAction: nextAction,
                at: date
            )
            _ = await refresh()
            return true
        } catch ClarificationError.actionRequiresNextStep {
            reviewError = "Add an outcome and one next action."
            return false
        } catch ThoughtLoopError.intentionCannotBeReviewed {
            reviewError = "Active or interrupted work stays unchanged. Finish or release it first."
            return false
        } catch {
            reviewError = "That review could not be saved. The original capture is still safe."
            return false
        }
    }

    @discardableResult
    func refresh() async -> Bool {
        await meetingController?.refresh()
        do {
            async let nextNow = readModels.now()
            async let nextReturns = readModels.returns()
            async let nextLater = readModels.later()
            async let nextOpenLoops = readModels.openLoops()
            async let nextReviews = readModels.reviewQueue()
            let projections = try await (
                nextNow,
                nextReturns,
                nextLater,
                nextOpenLoops,
                nextReviews
            )
            now = projections.0
            returns = projections.1
            later = projections.2
            openLoops = projections.3
            reviewItems = projections.4
            commandError = nil
            await refreshSemanticGraph()
            await refreshVoiceQualityAudit()
            return true
        } catch {
            commandError = "Saved locally, but the view could not refresh. Try reopening it."
            return false
        }
    }

    @discardableResult
    func startFocus(_ intentionID: UUID) async -> Bool {
        await runFocusCommand {
            try await $0.start(intentionID, at: .now)
        }
    }

    @discardableResult
    func pauseFocus(_ intentionID: UUID) async -> Bool {
        await runFocusCommand {
            try await $0.pause(intentionID, at: .now)
        }
    }

    @discardableResult
    func continueFocus(_ intentionID: UUID) async -> Bool {
        await runFocusCommand {
            try await $0.continueSession(intentionID, at: .now)
        }
    }

    func interruptFocus(_ intentionID: UUID, draft: InterruptionDraft) async -> Bool {
        await runFocusCommand {
            try await $0.interrupt(intentionID, draft: draft, at: .now)
        }
    }

    @discardableResult
    func resumeFocus(_ intentionID: UUID) async -> Bool {
        await runFocusCommand {
            try await $0.resume(intentionID, at: .now)
        }
    }

    @discardableResult
    func finishFocus(_ intentionID: UUID) async -> Bool {
        await runFocusCommand {
            try await $0.finish(intentionID, at: .now)
        }
    }

    @discardableResult
    func finishOpenLoop(_ intentionID: UUID) async -> Bool {
        guard let item = openLoops.first(where: { $0.id == intentionID }) else { return false }
        if item.state == .open {
            return await runThoughtCommand { try await self.loop.close(intentionID) }
        }
        return await finishFocus(intentionID)
    }

    @discardableResult
    func releaseOpenLoop(_ intentionID: UUID) async -> Bool {
        guard let item = openLoops.first(where: { $0.id == intentionID }) else { return false }
        if item.state == .open {
            return await runThoughtCommand { try await self.loop.release(intentionID) }
        }
        return await runFocusCommand { try await $0.release(intentionID, at: .now) }
    }

    @discardableResult
    func moveOpenLoop(_ intentionID: UUID, by offset: Int) async -> Bool {
        guard let index = openLoops.firstIndex(where: { $0.id == intentionID }) else { return false }
        let destination = min(max(0, index + offset), openLoops.count - 1)
        guard destination != index else { return true }
        var ids = openLoops.map(\.id)
        ids.swapAt(index, destination)
        return await runThoughtCommand {
            try await self.loop.reorderOpenIntentions(ids)
        }
    }

    @discardableResult
    func moveOpenLoop(_ intentionID: UUID, before targetID: UUID) async -> Bool {
        guard intentionID != targetID,
              let sourceIndex = openLoops.firstIndex(where: { $0.id == intentionID }),
              openLoops.contains(where: { $0.id == targetID }) else { return false }
        var ids = openLoops.map(\.id)
        let movedID = ids.remove(at: sourceIndex)
        guard let targetIndex = ids.firstIndex(of: targetID) else { return false }
        ids.insert(movedID, at: targetIndex)
        return await runThoughtCommand {
            try await self.loop.reorderOpenIntentions(ids)
        }
    }

    @discardableResult
    func chooseNext(_ intentionID: UUID) async -> Bool {
        guard let index = openLoops.firstIndex(where: { $0.id == intentionID }) else { return false }
        var ids = openLoops.map(\.id)
        let selected = ids.remove(at: index)
        let insertionIndex = ids.firstIndex { id in
            openLoops.first(where: { $0.id == id })?.state == .open
        } ?? 0
        ids.insert(selected, at: insertionIndex)
        return await runThoughtCommand {
            try await self.loop.reorderOpenIntentions(ids)
        }
    }

    @discardableResult
    private func runThoughtCommand<T>(_ operation: () async throws -> T) async -> Bool {
        commandError = nil
        do {
            _ = try await operation()
            return await refresh()
        } catch {
            commandError = "That task change could not be saved."
            return false
        }
    }

    func refreshPrivacy() async {
        guard let privacyManager else { return }
        do {
            async let summary = privacyManager.summary()
            async let policy = privacyManager.retentionPolicy()
            privacySummary = try await summary
            retentionPolicy = try await policy
            privacyError = nil
        } catch {
            privacyError = "Private storage details are unavailable right now."
        }
    }

    @discardableResult
    func applyRetention(_ policy: PrivacyRetentionPolicy, at date: Date = .now) async -> Bool {
        guard !isUpdatingPrivacy, let privacyManager else { return false }
        isUpdatingPrivacy = true
        privacyError = nil
        defer { isUpdatingPrivacy = false }
        do {
            let result = try await privacyManager.applyRetention(policy, at: date)
            retentionPolicy = policy
            privacyNotice = result.removedCaptures == 0
                ? "Retention preference saved. Nothing needed removal."
                : "Removed \(result.removedCaptures) old captures and their linked task data."
            recallQuery = ""
            recallHits = []
            await refreshPrivacy()
            _ = await refresh()
            await refreshMemory()
            return true
        } catch {
            privacyError = "Retention could not be applied. Stored data is unchanged."
            return false
        }
    }

    @discardableResult
    func createEncryptedBackup(at destination: URL) async -> Bool {
        guard !isUpdatingPrivacy, let privacyManager else { return false }
        isUpdatingPrivacy = true
        privacyError = nil
        defer { isUpdatingPrivacy = false }
        do {
            try await privacyManager.createEncryptedBackup(at: destination)
            privacyNotice = "Encrypted same-Mac backup saved."
            return true
        } catch {
            privacyError = "The encrypted backup could not be saved."
            return false
        }
    }

    @discardableResult
    func resetAllData() async -> Bool {
        guard !isUpdatingPrivacy, let privacyManager else { return false }
        isUpdatingPrivacy = true
        privacyError = nil
        defer { isUpdatingPrivacy = false }
        do {
            try await privacyManager.resetAllData()
            privacyNotice = "All OpenLoop data on this Mac was removed."
            recallQuery = ""
            recallHits = []
            memoryRecords = []
            contextTrailSettings = ContextTrailSettings()
            contextEpisodes = []
            suggestions = []
            resurfacingRules = []
            await refreshPrivacy()
            _ = await refresh()
            return true
        } catch {
            privacyError = "Data could not be reset. Stored data is unchanged."
            return false
        }
    }

    @discardableResult
    private func runFocusCommand(
        _ operation: (FocusLoop) async throws -> FocusUpdate
    ) async -> Bool {
        guard let focusLoop else {
            commandError = "Focus controls are unavailable."
            return false
        }
        commandError = nil
        do {
            _ = try await operation(focusLoop)
            let refreshed = await refresh()
            if let contextTrail, let currentApplication {
                _ = try? await contextTrail.observe(currentApplication, at: .now)
            }
            await refreshContextTrail()
            return refreshed
        } catch let FocusLoopError.currentFocusExists(id) {
            commandError = id == now?.intentionID
                ? "This intention is already in focus."
                : "Pause or interrupt the current focus before starting another."
            return false
        } catch {
            commandError = "That focus change could not be saved."
            return false
        }
    }
}
