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

    private let loop: ThoughtLoop
    private let readModels: ThoughtReadModels
    private let focusLoop: FocusLoop?
    private let resurfacingLoop: ResurfacingLoop?
    private let recallSearch: (any RecallSearching)?
    private let workingMemory: (any WorkingMemoryCompiling)?
    private let contextTrail: (any ContextTrailProviding)?
    private var recallGeneration = 0

    init(
        loop: ThoughtLoop,
        readModels: ThoughtReadModels,
        focusLoop: FocusLoop? = nil,
        resurfacingLoop: ResurfacingLoop? = nil,
        recallSearch: (any RecallSearching)? = nil,
        workingMemory: (any WorkingMemoryCompiling)? = nil,
        contextTrail: (any ContextTrailProviding)? = nil
    ) {
        self.loop = loop
        self.readModels = readModels
        self.focusLoop = focusLoop
        self.resurfacingLoop = resurfacingLoop
        self.recallSearch = recallSearch
        self.workingMemory = workingMemory
        self.contextTrail = contextTrail
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
    func refresh() async -> Bool {
        do {
            async let nextNow = readModels.now()
            async let nextReturns = readModels.returns()
            async let nextLater = readModels.later()
            async let nextOpenLoops = readModels.openLoops()
            let projections = try await (nextNow, nextReturns, nextLater, nextOpenLoops)
            now = projections.0
            returns = projections.1
            later = projections.2
            openLoops = projections.3
            commandError = nil
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
