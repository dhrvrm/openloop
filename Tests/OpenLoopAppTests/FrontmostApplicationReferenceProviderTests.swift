import Testing
@testable import OpenLoopApp

@Test func frontmostApplicationBecomesAReadableReference() async throws {
    let provider = FrontmostApplicationReferenceProvider { "  Safari  " }
    await provider.snapshot()

    #expect(try await provider.references() == ["Application — Safari"])
}

@Test func missingFrontmostApplicationProducesNoReference() async throws {
    let provider = FrontmostApplicationReferenceProvider { nil }
    await provider.snapshot()

    #expect(try await provider.references().isEmpty)
}
