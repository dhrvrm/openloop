import ADHDCore
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var captureError: String?
    @Published var isSaving = false
    @Published var now: NowItem?
    @Published var later: [LaterItem] = []

    private let loop: ThoughtLoop
    private let readModels: ThoughtReadModels

    init(loop: ThoughtLoop, readModels: ThoughtReadModels) {
        self.loop = loop
        self.readModels = readModels
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
                }
            }
            return true
        } catch {
            isSaving = false
            captureError = "Could not save. Your text is still here."
            return false
        }
    }

    func refresh() async {
        do {
            now = try await readModels.now()
            later = try await readModels.later()
        } catch {
            captureError = "Could not refresh local thoughts."
        }
    }
}
