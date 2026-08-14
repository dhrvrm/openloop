import ADHDCore
import AppKit
import Foundation

struct FrontmostApplicationReferenceProvider: ContextReferenceProvider {
    private let applicationName: @MainActor @Sendable () -> String?

    init(applicationName: @escaping @MainActor @Sendable () -> String?) {
        self.applicationName = applicationName
    }

    init() {
        applicationName = {
            NSWorkspace.shared.frontmostApplication?.localizedName
        }
    }

    func references() async throws -> [String] {
        guard let value = await applicationName() else { return [] }
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return [] }
        return ["Application — \(name)"]
    }
}
