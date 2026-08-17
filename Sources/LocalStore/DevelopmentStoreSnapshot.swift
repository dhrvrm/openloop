import ADHDCore
import Foundation

public struct DevelopmentStoreSnapshot: Codable, Equatable, Sendable {
    public let captures: [RawCapture]
    public let proposals: [ClarificationProposal]
    public let clarificationCorrections: [ClarificationCorrection]
    public let intentions: [Intention]

    public init(
        captures: [RawCapture],
        proposals: [ClarificationProposal],
        clarificationCorrections: [ClarificationCorrection] = [],
        intentions: [Intention]
    ) {
        self.captures = captures
        self.proposals = proposals
        self.clarificationCorrections = clarificationCorrections
        self.intentions = intentions
    }
}

extension DevelopmentStoreSnapshot {
    public static func load(from fileURL: URL) throws -> DevelopmentStoreSnapshot {
        struct LegacySnapshot: Codable {
            var captures: [UUID: RawCapture]
            var proposals: [UUID: ClarificationProposal]?
            var clarificationCorrections: [UUID: ClarificationCorrection]?
            var intentions: [UUID: Intention]
        }
        let legacy: LegacySnapshot
        do {
            legacy = try JSONDecoder().decode(
                LegacySnapshot.self,
                from: Data(contentsOf: fileURL)
            )
        } catch {
            throw JSONFileThoughtRepositoryError.corruptSnapshot
        }
        return DevelopmentStoreSnapshot(
            captures: legacy.captures.values.sorted(by: captureOrder),
            proposals: (legacy.proposals ?? [:]).values.sorted {
                $0.captureID.uuidString < $1.captureID.uuidString
            },
            clarificationCorrections: (legacy.clarificationCorrections ?? [:]).values.sorted {
                if $0.reviewedAt == $1.reviewedAt { return $0.id.uuidString < $1.id.uuidString }
                return $0.reviewedAt < $1.reviewedAt
            },
            intentions: legacy.intentions.values.sorted(by: intentionOrder)
        )
    }

    private static func captureOrder(_ lhs: RawCapture, _ rhs: RawCapture) -> Bool {
        if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.createdAt < rhs.createdAt
    }

    private static func intentionOrder(_ lhs: Intention, _ rhs: Intention) -> Bool {
        if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.createdAt < rhs.createdAt
    }
}

extension JSONFileThoughtRepository {
    public func developmentSnapshot() -> DevelopmentStoreSnapshot {
        DevelopmentStoreSnapshot(
            captures: snapshotCaptures(),
            proposals: snapshotProposals(),
            clarificationCorrections: snapshotClarificationCorrections(),
            intentions: snapshotIntentions()
        )
    }
}
