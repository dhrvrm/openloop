import ADHDCore
import Testing
@testable import OpenLoopApp

@Test func frontmostApplicationBecomesAReadableReference() async throws {
    let provider = FrontmostApplicationReferenceProvider {
        FrontmostApplicationIdentity(
            bundleIdentifier: "  COM.APPLE.SAFARI  ",
            applicationName: "  Safari  "
        )
    }
    await provider.snapshot()
    let expectedContext = try ApplicationContext(
        bundleIdentifier: "com.apple.safari",
        applicationName: "Safari"
    )

    #expect(try await provider.references() == ["Application — Safari"])
    #expect(await provider.currentContext() == expectedContext)
}

@Test func missingFrontmostApplicationProducesNoReference() async throws {
    let provider = FrontmostApplicationReferenceProvider { nil }
    await provider.snapshot()

    #expect(try await provider.references().isEmpty)
    #expect(await provider.currentContext() == nil)
}

@Test func incompleteApplicationIdentityProducesNoContextOrReference() async throws {
    let provider = FrontmostApplicationReferenceProvider {
        FrontmostApplicationIdentity(
            bundleIdentifier: nil,
            applicationName: "Editor"
        )
    }
    await provider.snapshot()

    #expect(await provider.currentContext() == nil)
    #expect(try await provider.references().isEmpty)
}
