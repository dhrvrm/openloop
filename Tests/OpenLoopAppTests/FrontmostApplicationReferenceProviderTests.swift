import Testing
@testable import OpenLoopApp

@Test func frontmostApplicationBecomesAReadableReference() async throws {
    let provider = FrontmostApplicationReferenceProvider { "  Safari  " }

    #expect(try await provider.references() == ["Application — Safari"])
}

@Test func missingFrontmostApplicationProducesNoReference() async throws {
    let provider = FrontmostApplicationReferenceProvider { nil }

    #expect(try await provider.references().isEmpty)
}
