import ADHDCore
import Foundation

private struct Snapshot: Codable {
    var captures: [UUID: RawCapture] = [:]
    var intentions: [UUID: Intention] = [:]
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

    public func save(intention: Intention) async throws {
        snapshot.intentions[intention.id] = intention
        try persist()
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

    private func persist() throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
