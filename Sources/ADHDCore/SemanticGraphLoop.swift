import Foundation

public actor SemanticGraphLoop {
    private let repository: any ThoughtRepository
    private let projection: SemanticGraphProjection
    private let embeddingProvider: (any EmbeddingProvider)?

    public init(
        repository: any ThoughtRepository,
        projection: SemanticGraphProjection = SemanticGraphProjection(),
        embeddingProvider: (any EmbeddingProvider)? = nil
    ) {
        self.repository = repository
        self.projection = projection
        self.embeddingProvider = embeddingProvider
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

    @discardableResult
    public func enrichVector(nodeID: UUID, text: String) async throws -> SemanticVector? {
        guard let embeddingProvider else { return nil }
        let initialGraph = try await graph()
        guard initialGraph.nodes[nodeID] != nil else { throw SemanticGraphError.missingNode(nodeID) }
        if let existing = initialGraph.vectors[nodeID] { return existing }
        guard let values = try await embeddingProvider.vectors(for: [text]).first else {
            return nil
        }
        let latestGraph = try await graph()
        if let existing = latestGraph.vectors[nodeID] { return existing }
        let vector = try SemanticVector(
            providerIdentifier: await embeddingProvider.identifier,
            values: values
        )
        var events: [SemanticGraphEvent] = [
            .vector(id: UUID(), occurredAt: vector.createdAt, nodeID: nodeID, value: vector),
        ]
        let existingPairs = Set(latestGraph.relations.values.map {
            Self.relationPair($0.sourceID, $0.targetID)
        })
        let related = latestGraph.vectors.compactMap { candidateID, candidate -> (UUID, Double)? in
            guard candidateID != nodeID,
                  candidate.providerIdentifier == vector.providerIdentifier,
                  candidate.values.count == vector.values.count else { return nil }
            let similarity = Self.cosineSimilarity(vector.values, candidate.values)
            guard similarity >= 0.55,
                  !existingPairs.contains(Self.relationPair(nodeID, candidateID)) else { return nil }
            return (candidateID, similarity)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.uuidString < $1.0.uuidString
        }.prefix(3)
        for (candidateID, similarity) in related {
            let relation = try SemanticRelation(
                sourceID: nodeID,
                targetID: candidateID,
                kind: .relatesTo,
                confidence: similarity
            )
            events.append(.relation(id: UUID(), occurredAt: .now, value: relation))
        }
        try await append(events)
        return vector
    }

    @discardableResult
    public func enrichMissingVectors(limit: Int = 64) async throws -> Int {
        let current = try await graph()
        let missing = current.nodes.values.filter {
            current.vectors[$0.id] == nil && $0.status != .superseded
        }.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }.prefix(max(0, limit))
        var enriched = 0
        for node in missing {
            if try await enrichVector(nodeID: node.id, text: node.claim) != nil {
                enriched += 1
            }
        }
        return enriched
    }

    @discardableResult
    public func synchronize(memoryRecords: [MemoryRecord]) async throws -> Int {
        var current = try await graph()
        var events: [SemanticGraphEvent] = []
        let orderedRecords = memoryRecords.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        for record in orderedRecords {
            let node = try Self.semanticNode(for: record)
            if current.nodes[node.id] != node {
                let event = SemanticGraphEvent.node(
                    id: UUID(),
                    occurredAt: record.updatedAt,
                    value: node
                )
                try current.apply(event)
                events.append(event)
            }
        }

        var existingPairs = Set(current.relations.values.map {
            Self.relationPair($0.sourceID, $0.targetID)
        })
        for record in orderedRecords {
            guard case .superseded(let replacementID) = record.state,
                  current.nodes[replacementID] != nil,
                  !existingPairs.contains(Self.relationPair(replacementID, record.id)) else { continue }
            let relation = try SemanticRelation(
                sourceID: replacementID,
                targetID: record.id,
                kind: .supersedes,
                confidence: 1,
                createdAt: record.updatedAt
            )
            let event = SemanticGraphEvent.relation(
                id: UUID(),
                occurredAt: record.updatedAt,
                value: relation
            )
            try current.apply(event)
            events.append(event)
            existingPairs.insert(Self.relationPair(replacementID, record.id))
        }
        try await append(events)
        return events.count
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

    private static func semanticNode(for record: MemoryRecord) throws -> SemanticNode {
        let status: SemanticNodeStatus
        let supersededBy: UUID?
        switch record.state {
        case .active:
            status = .active
            supersededBy = nil
        case .contradicted, .evidenceExpired:
            status = .resolved
            supersededBy = nil
        case .superseded(let id):
            status = .superseded
            supersededBy = id
        }
        return try SemanticNode(
            id: record.id,
            kind: semanticKind(for: record.kind),
            claim: record.statement,
            confidence: record.confidence,
            status: status,
            evidence: try record.evidence.map { evidence in
                try SemanticEvidence(
                    id: evidence.evidenceID,
                    excerpt: evidence.excerpt,
                    occurredAt: evidence.occurredAt
                )
            },
            createdAt: record.createdAt,
            supersededBy: supersededBy
        )
    }

    private static func semanticKind(for kind: MemoryKind) -> SemanticNodeKind {
        switch kind {
        case .fact: .knowledge
        case .decision: .decision
        case .commitment: .intention
        case .preference: .preference
        case .question: .question
        case .correction: .knowledge
        }
    }

    private static func relationPair(_ left: UUID, _ right: UUID) -> String {
        [left.uuidString, right.uuidString].sorted().joined(separator: "|")
    }

    private static func cosineSimilarity(_ left: [Double], _ right: [Double]) -> Double {
        guard !left.isEmpty, left.count == right.count else { return 0 }
        let dot = zip(left, right).reduce(0) { $0 + $1.0 * $1.1 }
        let leftLength = sqrt(left.reduce(0) { $0 + $1 * $1 })
        let rightLength = sqrt(right.reduce(0) { $0 + $1 * $1 })
        guard leftLength > 0, rightLength > 0 else { return 0 }
        return min(1, max(-1, dot / (leftLength * rightLength)))
    }
}
