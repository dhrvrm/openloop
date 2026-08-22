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

    /// Records the raw observation plus conservative, evidence-linked meaning.
    /// Replaying the same capture is idempotent and never invents a task.
    @discardableResult
    public func recordSemantics(
        capture: RawCapture,
        extractor: SemanticCandidateExtractor = SemanticCandidateExtractor()
    ) async throws -> [SemanticNode] {
        let evidenceID = RecallEvidenceID(kind: .capture, id: capture.id)
        let current = try await graph()
        let existing = current.nodes.values.filter { node in
            node.evidence.contains { $0.id == evidenceID }
        }.sorted { left, right in
            if left.id == capture.id { return true }
            if right.id == capture.id { return false }
            return left.id.uuidString < right.id.uuidString
        }
        if current.nodes[capture.id] != nil { return existing }

        let evidence = try SemanticEvidence(
            id: evidenceID,
            excerpt: capture.text,
            occurredAt: capture.createdAt
        )
        let observation = try SemanticNode(
            id: capture.id,
            kind: .observation,
            claim: capture.text,
            confidence: 1,
            status: .active,
            evidence: [evidence],
            createdAt: capture.createdAt
        )
        var nodes = [observation]
        var events: [SemanticGraphEvent] = [
            .node(id: UUID(), occurredAt: capture.createdAt, value: observation),
        ]
        for candidate in extractor.extract(from: capture.text) {
            let node = try SemanticNode(
                kind: candidate.kind,
                claim: candidate.claim,
                confidence: candidate.confidence,
                status: candidate.status,
                evidence: [evidence],
                createdAt: capture.createdAt
            )
            let relation = try SemanticRelation(
                sourceID: observation.id,
                targetID: node.id,
                kind: .supports,
                confidence: candidate.confidence,
                createdAt: capture.createdAt
            )
            nodes.append(node)
            events.append(.node(id: UUID(), occurredAt: capture.createdAt, value: node))
            events.append(.relation(id: UUID(), occurredAt: capture.createdAt, value: relation))
        }
        try await append(events)
        return nodes
    }

    /// Projects only extractive meeting insights into the graph. Every node
    /// points back to the exact transcript segment that justified it.
    @discardableResult
    public func recordMeetingSemantics(
        transcript: MeetingTranscript,
        compiler: MeetingIntelligenceCompiler = MeetingIntelligenceCompiler()
    ) async throws -> [SemanticNode] {
        var current = try await graph()
        var events: [SemanticGraphEvent] = []
        var created: [SemanticNode] = []
        let rootEvidence = try SemanticEvidence(
            id: RecallEvidenceID(kind: .meetingTranscript, id: transcript.id),
            excerpt: String(transcript.text.prefix(512)),
            occurredAt: transcript.createdAt
        )
        let root: SemanticNode
        if let existing = current.nodes[transcript.id] {
            root = existing
        } else {
            root = try SemanticNode(
                id: transcript.id,
                kind: .context,
                claim: "Meeting: \(transcript.sourceName)",
                confidence: 1,
                status: .active,
                evidence: [rootEvidence],
                createdAt: transcript.createdAt
            )
            let event = SemanticGraphEvent.node(
                id: UUID(),
                occurredAt: transcript.createdAt,
                value: root
            )
            try current.apply(event)
            events.append(event)
            created.append(root)
        }

        let intelligence = compiler.compile(transcript)
        let insights: [(MeetingInsight, SemanticNodeKind, Double, SemanticNodeStatus)] =
            intelligence.summary.map { ($0, .observation, 0.76, .active) }
            + intelligence.questions.map { ($0, .question, 0.98, .active) }
            + intelligence.decisions.map { ($0, .decision, 0.96, .active) }
            + intelligence.actionCandidates.map { ($0, .intention, 0.94, .active) }

        for (insight, kind, confidence, status) in insights {
            let evidenceID = RecallEvidenceID(
                kind: .meetingTranscript,
                id: insight.evidence.segmentID
            )
            let exists = current.nodes.values.contains { node in
                node.kind == kind && node.claim == insight.text
                    && node.evidence.contains { $0.id == evidenceID }
            }
            guard !exists else { continue }
            let evidence = try SemanticEvidence(
                id: evidenceID,
                excerpt: insight.evidence.excerpt,
                occurredAt: transcript.createdAt.addingTimeInterval(insight.evidence.start)
            )
            let node = try SemanticNode(
                kind: kind,
                claim: insight.text,
                confidence: confidence,
                status: status,
                evidence: [evidence],
                createdAt: evidence.occurredAt
            )
            let nodeEvent = SemanticGraphEvent.node(
                id: UUID(),
                occurredAt: node.createdAt,
                value: node
            )
            try current.apply(nodeEvent)
            events.append(nodeEvent)
            let relation = try SemanticRelation(
                sourceID: root.id,
                targetID: node.id,
                kind: .supports,
                confidence: confidence,
                createdAt: node.createdAt
            )
            let relationEvent = SemanticGraphEvent.relation(
                id: UUID(),
                occurredAt: node.createdAt,
                value: relation
            )
            try current.apply(relationEvent)
            events.append(relationEvent)
            created.append(node)
        }
        try await append(events)
        return created
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

    /// Condenses recurring derived meanings while preserving every original
    /// node and evidence excerpt in append-only history. Raw observations and
    /// meeting contexts are never auto-superseded.
    @discardableResult
    public func consolidateRecurringClaims(
        minimumOccurrences: Int = 3,
        minimumSimilarity: Double = 0.86
    ) async throws -> [SemanticNode] {
        guard minimumOccurrences >= 2,
              minimumSimilarity.isFinite,
              (0...1).contains(minimumSimilarity) else { return [] }
        let current = try await graph()
        let eligibleKinds: Set<SemanticNodeKind> = [.problem, .idea, .possibility, .concept]
        let eligible = current.nodes.filter { _, node in
            eligibleKinds.contains(node.kind) && node.status != .superseded
        }
        var adjacency = Dictionary(uniqueKeysWithValues: eligible.keys.map { ($0, Set<UUID>()) })
        for relation in current.relations.values where
            relation.kind == .relatesTo && relation.confidence >= minimumSimilarity {
            guard let source = eligible[relation.sourceID],
                  let target = eligible[relation.targetID],
                  source.kind == target.kind else { continue }
            adjacency[source.id, default: []].insert(target.id)
            adjacency[target.id, default: []].insert(source.id)
        }

        var visited = Set<UUID>()
        var components: [[SemanticNode]] = []
        for start in eligible.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard visited.insert(start).inserted else { continue }
            var queue = [start]
            var component: [SemanticNode] = []
            while let nodeID = queue.popLast() {
                guard let node = eligible[nodeID] else { continue }
                component.append(node)
                for neighbor in adjacency[nodeID, default: []]
                    .sorted(by: { $0.uuidString > $1.uuidString })
                    where visited.insert(neighbor).inserted {
                    queue.append(neighbor)
                }
            }
            if component.count >= minimumOccurrences { components.append(component) }
        }

        var events: [SemanticGraphEvent] = []
        var consolidated: [SemanticNode] = []
        for component in components {
            let ordered = component.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard let latest = ordered.last else { continue }
            var evidenceIDs = Set<RecallEvidenceID>()
            let evidence = ordered.flatMap(\.evidence).filter {
                evidenceIDs.insert($0.id).inserted
            }.sorted {
                if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
                return $0.id.id.uuidString < $1.id.id.uuidString
            }
            let averageConfidence = ordered.map(\.confidence).reduce(0, +)
                / Double(ordered.count)
            let node = try SemanticNode(
                kind: latest.kind,
                claim: latest.claim,
                confidence: averageConfidence,
                status: ordered.contains(where: { $0.status == .active }) ? .active : .speculative,
                evidence: evidence,
                createdAt: latest.createdAt
            )
            events.append(.node(id: UUID(), occurredAt: node.createdAt, value: node))

            let vectors = ordered.compactMap { current.vectors[$0.id] }
            if vectors.count == ordered.count,
               let first = vectors.first,
               vectors.allSatisfy({
                   $0.providerIdentifier == first.providerIdentifier
                       && $0.values.count == first.values.count
               }) {
                let averaged = first.values.indices.map { index in
                    vectors.map { $0.values[index] }.reduce(0, +) / Double(vectors.count)
                }
                let vector = try SemanticVector(
                    providerIdentifier: first.providerIdentifier,
                    values: averaged,
                    createdAt: node.createdAt
                )
                events.append(.vector(
                    id: UUID(),
                    occurredAt: node.createdAt,
                    nodeID: node.id,
                    value: vector
                ))
            }
            for old in ordered {
                events.append(.supersession(
                    id: UUID(),
                    occurredAt: node.createdAt,
                    oldID: old.id,
                    newID: node.id
                ))
            }
            consolidated.append(node)
        }
        try await append(events)
        return consolidated
    }

    public func ask(_ query: String, limit: Int = 5) async throws -> [SemanticAnswer] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryTerms = Self.terms(query)
        guard !queryTerms.isEmpty, limit > 0 else { return [] }
        let graph = try await graph()
        let queryEmbedding = await queryEmbedding(for: query)
        let dates = graph.nodes.values.map(\.createdAt)
        let oldest = dates.min() ?? .distantPast
        let newest = dates.max() ?? oldest
        let dateRange = newest.timeIntervalSince(oldest)
        let maximumDegree = max(1, graph.nodes.keys.map { Self.degree(of: $0, in: graph) }.max() ?? 1)

        var ranked: [SemanticAnswer] = []
        for source in graph.nodes.values {
            let lexical = Self.lexicalRelevance(queryTerms, claim: source.claim)
            let vector = Self.vectorRelevance(
                nodeID: source.id,
                graph: graph,
                queryEmbedding: queryEmbedding
            )
            guard lexical > 0 || vector >= 0.55 else { continue }

            let node = Self.currentNode(for: source, in: graph)
            let degree = Double(Self.degree(of: node.id, in: graph)) / Double(maximumDegree)
            let recency = dateRange > 0
                ? node.createdAt.timeIntervalSince(oldest) / dateRange
                : 1
            let evidence = min(1, Double(node.evidence.count) / 3)
            let relevance = (lexical * 0.40)
                + (max(0, vector) * 0.32)
                + (degree * 0.08)
                + (node.confidence * 0.08)
                + (recency * 0.06)
                + (evidence * 0.06)
            let related = Self.relatedNodes(to: node.id, in: graph, including: source)
            let history = Self.history(for: node.id, matchedNodeID: source.id, in: graph)
            ranked.append(SemanticAnswer(
                node: node,
                relevance: relevance,
                related: related,
                history: history
            ))
        }

        var seenNodes = Set<UUID>()
        var seenClaims = Set<String>()
        return ranked.sorted {
            if $0.relevance != $1.relevance { return $0.relevance > $1.relevance }
            if $0.node.confidence != $1.node.confidence {
                return $0.node.confidence > $1.node.confidence
            }
            if $0.node.createdAt != $1.node.createdAt {
                return $0.node.createdAt > $1.node.createdAt
            }
            return $0.node.id.uuidString < $1.node.id.uuidString
        }.filter { answer in
            let claim = answer.node.claim.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: nil
            ).split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .joined(separator: " ")
            return seenNodes.insert(answer.node.id).inserted
                && seenClaims.insert(claim).inserted
        }
            .prefix(limit)
            .map { $0 }
    }

    private func queryEmbedding(for query: String) async -> (identifier: String, values: [Double])? {
        guard let embeddingProvider else { return nil }
        do {
            guard let values = try await embeddingProvider.vectors(for: [query]).first,
                  !values.isEmpty else { return nil }
            return (await embeddingProvider.identifier, values)
        } catch {
            return nil
        }
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

    private static func terms(_ value: String) -> Set<String> {
        Set(value.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    private static func lexicalRelevance(_ queryTerms: Set<String>, claim: String) -> Double {
        guard !queryTerms.isEmpty else { return 0 }
        let claimTerms = terms(claim)
        return Double(queryTerms.intersection(claimTerms).count) / Double(queryTerms.count)
    }

    private static func vectorRelevance(
        nodeID: UUID,
        graph: SemanticGraph,
        queryEmbedding: (identifier: String, values: [Double])?
    ) -> Double {
        guard let queryEmbedding,
              let vector = graph.vectors[nodeID],
              vector.providerIdentifier == queryEmbedding.identifier,
              vector.values.count == queryEmbedding.values.count else { return 0 }
        return cosineSimilarity(vector.values, queryEmbedding.values)
    }

    private static func currentNode(for source: SemanticNode, in graph: SemanticGraph) -> SemanticNode {
        var current = source
        var visited = Set<UUID>()
        while current.status == .superseded,
              let replacementID = current.supersededBy,
              visited.insert(current.id).inserted,
              let replacement = graph.nodes[replacementID] {
            current = replacement
        }
        return current
    }

    private static func degree(of nodeID: UUID, in graph: SemanticGraph) -> Int {
        graph.relations.values.reduce(0) { count, relation in
            count + ((relation.sourceID == nodeID || relation.targetID == nodeID) ? 1 : 0)
        }
    }

    private static func relatedNodes(
        to nodeID: UUID,
        in graph: SemanticGraph,
        including matchedNode: SemanticNode
    ) -> [SemanticNode] {
        let linked = graph.relations.values.compactMap { relation -> (SemanticNode, Double)? in
            let otherID: UUID
            if relation.sourceID == nodeID {
                otherID = relation.targetID
            } else if relation.targetID == nodeID {
                otherID = relation.sourceID
            } else {
                return nil
            }
            guard let node = graph.nodes[otherID] else { return nil }
            return (node, relation.confidence)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.createdAt > $1.0.createdAt
        }.map(\.0)

        var seen = Set<UUID>()
        var result = linked.filter { seen.insert($0.id).inserted }
        if matchedNode.id != nodeID, seen.insert(matchedNode.id).inserted {
            result.insert(matchedNode, at: 0)
        }
        return result
    }

    private static func history(
        for nodeID: UUID,
        matchedNodeID: UUID,
        in graph: SemanticGraph
    ) -> [SemanticGraphEvent] {
        let combined = graph.history(for: nodeID)
            + (matchedNodeID == nodeID ? [] : graph.history(for: matchedNodeID))
        var seen = Set<UUID>()
        return combined.filter { seen.insert($0.id).inserted }.sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
            return $0.id.uuidString < $1.id.uuidString
        }
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
