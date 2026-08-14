import ADHDCore
import Foundation

private struct Snapshot: Codable {
    var captures: [UUID: RawCapture] = [:]
    var proposals: [UUID: ClarificationProposal] = [:]
    var intentions: [UUID: Intention] = [:]

    private enum CodingKeys: String, CodingKey {
        case captures
        case proposals
        case intentions
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        captures = try container.decode([UUID: RawCapture].self, forKey: .captures)
        proposals = try container.decodeIfPresent(
            [UUID: ClarificationProposal].self,
            forKey: .proposals
        ) ?? [:]
        intentions = try container.decode([UUID: Intention].self, forKey: .intentions)
    }
}

public enum JSONFileThoughtRepositoryError: Error, Equatable {
    case corruptSnapshot
}

public actor JSONFileThoughtRepository: ThoughtRepository {
    private let fileURL: URL
    private var snapshot: Snapshot

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        fileURL = directory.appendingPathComponent("thought-loop.json")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            do {
                snapshot = try JSONDecoder().decode(
                    Snapshot.self,
                    from: data
                )
            } catch {
                throw JSONFileThoughtRepositoryError.corruptSnapshot
            }
        } else {
            snapshot = Snapshot()
        }
    }

    public func save(capture: RawCapture) async throws {
        snapshot.captures[capture.id] = capture
        try persist()
    }

    public func save(proposal: ClarificationProposal) async throws {
        snapshot.proposals[proposal.captureID] = proposal
        try persist()
    }

    public func save(intention: Intention) async throws {
        snapshot.intentions[intention.id] = intention
        try persist()
    }

    public func proposal(captureID: UUID) async throws -> ClarificationProposal? {
        snapshot.proposals[captureID]
    }

    public func captures(disposition: Disposition) async throws -> [RawCapture] {
        snapshot.captures.values
            .filter { snapshot.proposals[$0.id]?.disposition == disposition }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.createdAt < $1.createdAt
            }
    }

    public func intention(id: UUID) async throws -> Intention? {
        snapshot.intentions[id]
    }

    public func openIntentions() async throws -> [Intention] {
        snapshot.intentions.values
            .filter { $0.state != .closed && $0.state != .released }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.createdAt < $1.createdAt
            }
    }

    func snapshotCaptures() -> [RawCapture] {
        snapshot.captures.values.sorted(by: Self.captureOrder)
    }

    func snapshotProposals() -> [ClarificationProposal] {
        snapshot.proposals.values.sorted { $0.captureID.uuidString < $1.captureID.uuidString }
    }

    func snapshotIntentions() -> [Intention] {
        snapshot.intentions.values.sorted(by: Self.intentionOrder)
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
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
