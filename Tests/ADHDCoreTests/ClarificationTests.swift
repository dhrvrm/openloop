import Foundation
import Testing
@testable import ADHDCore

@Test func actionRequiresOutcomeAndNextAction() {
    #expect(throws: ClarificationError.actionRequiresNextStep) {
        try ClarificationProposal(
            captureID: UUID(),
            disposition: .action,
            desiredOutcome: "Send the flow",
            nextAction: nil,
            confidence: 0.8
        )
    }
}

@Test func memoryDoesNotInventAnAction() throws {
    let proposal = try ClarificationProposal(
        captureID: UUID(),
        disposition: .memory,
        desiredOutcome: nil,
        nextAction: nil,
        confidence: 1
    )

    #expect(proposal.nextAction == nil)
}

@Test func confidenceMustBeNormalized() {
    #expect(throws: ClarificationError.invalidConfidence) {
        try ClarificationProposal(
            captureID: UUID(),
            disposition: .unclear,
            desiredOutcome: nil,
            nextAction: nil,
            confidence: 1.1
        )
    }
}
