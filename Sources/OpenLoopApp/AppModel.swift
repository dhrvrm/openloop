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

    private let loop: ThoughtLoop
    private let readModels: ThoughtReadModels
    private let focusLoop: FocusLoop?

    init(
        loop: ThoughtLoop,
        readModels: ThoughtReadModels,
        focusLoop: FocusLoop? = nil
    ) {
        self.loop = loop
        self.readModels = readModels
        self.focusLoop = focusLoop
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

    func refresh() async {
        do {
            async let nextNow = readModels.now()
            async let nextReturns = readModels.returns()
            async let nextLater = readModels.later()
            now = try await nextNow
            returns = try await nextReturns
            later = try await nextLater
        } catch {
            captureError = "Could not refresh local thoughts."
        }
    }

    func startFocus(_ intentionID: UUID) async {
        await runFocusCommand {
            try await $0.start(intentionID, at: .now)
        }
    }

    func pauseFocus(_ intentionID: UUID) async {
        await runFocusCommand {
            try await $0.pause(intentionID, at: .now)
        }
    }

    func continueFocus(_ intentionID: UUID) async {
        await runFocusCommand {
            try await $0.continueSession(intentionID, at: .now)
        }
    }

    func interruptFocus(_ intentionID: UUID, draft: InterruptionDraft) async -> Bool {
        await runFocusCommand {
            try await $0.interrupt(intentionID, draft: draft, at: .now)
        }
    }

    func resumeFocus(_ intentionID: UUID) async {
        await runFocusCommand {
            try await $0.resume(intentionID, at: .now)
        }
    }

    func finishFocus(_ intentionID: UUID) async {
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
            await refresh()
            return true
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
