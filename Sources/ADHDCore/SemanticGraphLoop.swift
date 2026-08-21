import Foundation

public actor SemanticGraphLoop {
    private let repository: any ThoughtRepository
    private let projection: SemanticGraphProjection

    public init(
        repository: any ThoughtRepository,
        projection: SemanticGraphProjection = SemanticGraphProjection()
    ) {
        self.repository = repository
        self.projection = projection
    }

    public func graph() async throws -> SemanticGraph {
        try SemanticGraph(events: await repository.semanticGraphEvents())
    }

    public func append(_ events: [SemanticGraphEvent]) async throws {
        guard !events.isEmpty else { return }
        try await repository.append(semanticGraphEvents: events)
    }

    @discardableResult
    public func recordObservation(capture: RawCapture) async throws -> SemanticNode {
        let evidence = try SemanticEvidence(
            id: RecallEvidenceID(kind: .capture, id: capture.id),
            excerpt: capture.text,
            occurredAt: capture.createdAt
        )
        let node = try SemanticNode(
            id: capture.id,
            kind: .observation,
            claim: capture.text,
            confidence: 1,
            status: .active,
            evidence: [evidence],
            createdAt: capture.createdAt
        )
        try await append([
            .node(id: UUID(), occurredAt: capture.createdAt, value: node),
        ])
        return node
    }

    public func emerging(limit: Int = 8) async throws -> [SemanticThread] {
        projection.emerging(in: try await graph(), limit: limit)
    }

    public func unresolved() async throws -> [SemanticNode] {
        projection.unresolved(in: try await graph())
    }

    public func ask(_ query: String, limit: Int = 5) async throws -> [SemanticNode] {
        projection.ask(query, in: try await graph(), limit: limit)
    }
}
