import ADHDCore
import AppKit
import Foundation

struct FrontmostApplicationIdentity: Equatable, Sendable {
    let bundleIdentifier: String?
    let applicationName: String?
}

actor FrontmostApplicationReferenceProvider: ContextReferenceProvider {
    private let applicationIdentity: @MainActor @Sendable () -> FrontmostApplicationIdentity?
    private var capturedContext: ApplicationContext?

    init(
        applicationIdentity: @escaping @MainActor @Sendable () -> FrontmostApplicationIdentity?
    ) {
        self.applicationIdentity = applicationIdentity
    }

    init() {
        applicationIdentity = {
            guard let application = NSWorkspace.shared.frontmostApplication,
                  application.bundleIdentifier != Bundle.main.bundleIdentifier else {
                return nil
            }
            return FrontmostApplicationIdentity(
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.localizedName
            )
        }
    }

    func snapshot() async {
        capturedContext = nil
        guard let identity = await applicationIdentity(),
              let bundleIdentifier = identity.bundleIdentifier,
              let applicationName = identity.applicationName else {
            return
        }
        capturedContext = try? ApplicationContext(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName
        )
    }

    func currentContext() -> ApplicationContext? {
        capturedContext
    }

    func references() async throws -> [String] {
        capturedContext.map { ["Application — \($0.applicationName)"] } ?? []
    }
}
