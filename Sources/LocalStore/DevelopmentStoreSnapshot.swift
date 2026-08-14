import ADHDCore
import Foundation

public struct DevelopmentStoreSnapshot: Codable, Equatable, Sendable {
    public let captures: [RawCapture]
    public let proposals: [ClarificationProposal]
    public let intentions: [Intention]

    public init(
        captures: [RawCapture],
        proposals: [ClarificationProposal],
        intentions: [Intention]
    ) {
        self.captures = captures
        self.proposals = proposals
        self.intentions = intentions
    }
}

extension JSONFileThoughtRepository {
    public func developmentSnapshot() -> DevelopmentStoreSnapshot {
        DevelopmentStoreSnapshot(
            captures: snapshotCaptures(),
            proposals: snapshotProposals(),
            intentions: snapshotIntentions()
        )
    }
}
