import ADHDCore
import AppKit
import Foundation

actor FrontmostApplicationReferenceProvider: ContextReferenceProvider {
    private let applicationName: @MainActor @Sendable () -> String?
    private var capturedReference: String?

    init(applicationName: @escaping @MainActor @Sendable () -> String?) {
        self.applicationName = applicationName
    }

    init() {
        applicationName = {
            guard let application = NSWorkspace.shared.frontmostApplication,
                  application.bundleIdentifier != Bundle.main.bundleIdentifier else {
                return nil
            }
            return application.localizedName
        }
    }

    func snapshot() async {
        capturedReference = nil
        guard let value = await applicationName() else { return }
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        capturedReference = name.isEmpty ? nil : "Application — \(name)"
    }

    func references() async throws -> [String] {
        capturedReference.map { [$0] } ?? []
    }
}
