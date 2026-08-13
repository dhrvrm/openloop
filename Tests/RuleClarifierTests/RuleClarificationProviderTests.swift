import ADHDCore
import Foundation
import Testing
@testable import RuleClarifier

@Test(arguments: ["remember", "note", "idea"])
func memoryPrefixesRemainMemories(prefix: String) async throws {
    let provider = RuleClarificationProvider()
    let capture = try RawCapture(createdAt: .now, text: "\(prefix): Riya prefers email")
    let proposal = try await provider.propose(for: capture)

    #expect(proposal.disposition == .memory)
    #expect(proposal.nextAction == nil)
}

@Test func explicitActionUsesTheTextAsAReviewableNextStep() async throws {
    let provider = RuleClarificationProvider()
    let capture = try RawCapture(createdAt: .now, text: "todo: open the Figma file")
    let proposal = try await provider.propose(for: capture)

    #expect(proposal.disposition == .action)
    #expect(proposal.nextAction == "open the Figma file")
    #expect(proposal.confidence < 1)
}

@Test func ordinaryTextRemainsUnclearInsteadOfBecomingAFakeTask() async throws {
    let provider = RuleClarificationProvider()
    let capture = try RawCapture(createdAt: .now, text: "the launch conversation felt confusing")
    let proposal = try await provider.propose(for: capture)

    #expect(proposal.disposition == .unclear)
}

@Test func emptyActionPrefixRemainsUnclear() async throws {
    let provider = RuleClarificationProvider()
    let capture = try RawCapture(createdAt: .now, text: "todo:")
    let proposal = try await provider.propose(for: capture)

    #expect(proposal.disposition == .unclear)
}
