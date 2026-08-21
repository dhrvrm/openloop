import Foundation

public enum SemanticNodeKind: String, Codable, CaseIterable, Sendable {
    case observation, context, intent, knowledge, project, person, concept
    case decision, idea, intention, question, preference, problem, possibility, action
}

public enum SemanticNodeStatus: String, Codable, Sendable {
    case speculative, active, resolved, superseded
}

public enum SemanticRelationKind: String, Codable, Sendable {
    case relatesTo, partOf, mentions, causedBy, supports, contradicts, supersedes, suggestsAction
}

public enum SemanticGraphError: Error, Equatable {
    case emptyClaim
    case invalidConfidence
    case missingEvidence
    case missingNode(UUID)
    case selfRelation
    case duplicateEvent(UUID)
    case invalidVectorDimensions(Int)
    case invalidVectorValue
}

public struct SemanticVector: Codable, Equatable, Sendable {
    public static let minimumDimensions = 3
    public static let maximumDimensions = 4_096

    public let providerIdentifier: String
    public let values: [Double]
    public let createdAt: Date

    public init(
        providerIdentifier: String,
        values: [Double],
        createdAt: Date = .now
    ) throws {
        let identifier = providerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, values.allSatisfy(\.isFinite) else {
            throw SemanticGraphError.invalidVectorValue
        }
        guard (Self.minimumDimensions...Self.maximumDimensions).contains(values.count) else {
            throw SemanticGraphError.invalidVectorDimensions(values.count)
        }
        self.providerIdentifier = identifier
        self.values = values
        self.createdAt = createdAt
    }
}

public struct SemanticEvidence: Codable, Equatable, Sendable {
    public let id: RecallEvidenceID
    public let excerpt: String
    public let occurredAt: Date

    public init(id: RecallEvidenceID, excerpt: String, occurredAt: Date) throws {
        let excerpt = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !excerpt.isEmpty else { throw SemanticGraphError.missingEvidence }
        self.id = id
        self.excerpt = excerpt
        self.occurredAt = occurredAt
    }
}

public struct SemanticNode: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: SemanticNodeKind
    public let claim: String
    public let confidence: Double
    public let status: SemanticNodeStatus
    public let evidence: [SemanticEvidence]
    public let createdAt: Date
    public let supersededBy: UUID?

    public init(
        id: UUID = UUID(),
        kind: SemanticNodeKind,
        claim: String,
        confidence: Double,
        status: SemanticNodeStatus,
        evidence: [SemanticEvidence],
        createdAt: Date = .now,
        supersededBy: UUID? = nil
    ) throws {
        let claim = claim.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !claim.isEmpty else { throw SemanticGraphError.emptyClaim }
        guard confidence.isFinite, (0...1).contains(confidence) else {
            throw SemanticGraphError.invalidConfidence
        }
        guard !evidence.isEmpty else { throw SemanticGraphError.missingEvidence }
        self.id = id
        self.kind = kind
        self.claim = claim
        self.confidence = confidence
        self.status = status
        self.evidence = evidence
        self.createdAt = createdAt
        self.supersededBy = supersededBy
    }

    public func superseded(by id: UUID) throws -> SemanticNode {
        try SemanticNode(
            id: self.id,
            kind: kind,
            claim: claim,
            confidence: confidence,
            status: .superseded,
            evidence: evidence,
            createdAt: createdAt,
            supersededBy: id
        )
    }
}

public struct SemanticRelation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sourceID: UUID
    public let targetID: UUID
    public let kind: SemanticRelationKind
    public let confidence: Double
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sourceID: UUID,
        targetID: UUID,
        kind: SemanticRelationKind,
        confidence: Double,
        createdAt: Date = .now
    ) throws {
        guard sourceID != targetID else { throw SemanticGraphError.selfRelation }
        guard confidence.isFinite, (0...1).contains(confidence) else {
            throw SemanticGraphError.invalidConfidence
        }
        self.id = id
        self.sourceID = sourceID
        self.targetID = targetID
        self.kind = kind
        self.confidence = confidence
        self.createdAt = createdAt
    }
}

public enum SemanticGraphEvent: Codable, Equatable, Identifiable, Sendable {
    case node(id: UUID, occurredAt: Date, value: SemanticNode)
    case relation(id: UUID, occurredAt: Date, value: SemanticRelation)
    case supersession(id: UUID, occurredAt: Date, oldID: UUID, newID: UUID)
    case vector(id: UUID, occurredAt: Date, nodeID: UUID, value: SemanticVector)

    public var id: UUID {
        switch self {
        case .node(let id, _, _),
             .relation(let id, _, _),
             .supersession(let id, _, _, _),
             .vector(let id, _, _, _):
            id
        }
    }

    public var occurredAt: Date {
        switch self {
        case .node(_, let occurredAt, _),
             .relation(_, let occurredAt, _),
             .supersession(_, let occurredAt, _, _),
             .vector(_, let occurredAt, _, _):
            occurredAt
        }
    }
}

public struct SemanticGraph: Codable, Equatable, Sendable {
    public private(set) var events: [SemanticGraphEvent]
    public private(set) var nodes: [UUID: SemanticNode]
    public private(set) var relations: [UUID: SemanticRelation]
    public private(set) var vectors: [UUID: SemanticVector]

    public init(events: [SemanticGraphEvent] = []) throws {
        self.events = []
        nodes = [:]
        relations = [:]
        vectors = [:]
        for event in events { try apply(event) }
    }

    public mutating func apply(_ event: SemanticGraphEvent) throws {
        guard events.contains(where: { $0.id == event.id }) == false else {
            throw SemanticGraphError.duplicateEvent(event.id)
        }
        switch event {
        case .node(_, _, let value):
            nodes[value.id] = value
        case .relation(_, _, let value):
            guard nodes[value.sourceID] != nil else { throw SemanticGraphError.missingNode(value.sourceID) }
            guard nodes[value.targetID] != nil else { throw SemanticGraphError.missingNode(value.targetID) }
            relations[value.id] = value
        case .supersession(_, _, let oldID, let newID):
            guard let old = nodes[oldID] else { throw SemanticGraphError.missingNode(oldID) }
            guard nodes[newID] != nil else { throw SemanticGraphError.missingNode(newID) }
            nodes[oldID] = try old.superseded(by: newID)
            let relation = try SemanticRelation(
                sourceID: newID,
                targetID: oldID,
                kind: .supersedes,
                confidence: 1
            )
            relations[relation.id] = relation
        case .vector(_, _, let nodeID, let value):
            guard nodes[nodeID] != nil else { throw SemanticGraphError.missingNode(nodeID) }
            vectors[nodeID] = value
        }
        events.append(event)
    }

    public func history(for nodeID: UUID) -> [SemanticGraphEvent] {
        events.filter { event in
            switch event {
            case .node(_, _, let node): node.id == nodeID
            case .relation(_, _, let relation):
                relation.sourceID == nodeID || relation.targetID == nodeID
            case .supersession(_, _, let oldID, let newID):
                oldID == nodeID || newID == nodeID
            case .vector(_, _, let vectorNodeID, _):
                vectorNodeID == nodeID
            }
        }
    }
}

public struct SemanticThread: Equatable, Identifiable, Sendable {
    public let node: SemanticNode
    public let related: [SemanticNode]
    public let strength: Int
    public var id: UUID { node.id }
}

public struct SemanticGraphProjection: Sendable {
    public init() {}

    public func emerging(in graph: SemanticGraph, limit: Int = 8) -> [SemanticThread] {
        graph.nodes.values.filter {
            $0.status != .superseded && [.project, .concept, .problem, .idea].contains($0.kind)
        }.map { node in
            let connectedIDs = graph.relations.values.compactMap { relation -> UUID? in
                if relation.sourceID == node.id { return relation.targetID }
                if relation.targetID == node.id { return relation.sourceID }
                return nil
            }
            return SemanticThread(
                node: node,
                related: connectedIDs.compactMap { graph.nodes[$0] },
                strength: connectedIDs.count + node.evidence.count
            )
        }.sorted {
            if $0.strength != $1.strength { return $0.strength > $1.strength }
            return $0.node.createdAt > $1.node.createdAt
        }.prefix(max(0, limit)).map { $0 }
    }

    public func unresolved(in graph: SemanticGraph) -> [SemanticNode] {
        graph.nodes.values.filter {
            ($0.kind == .problem || $0.kind == .question) && $0.status == .active
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func ask(_ query: String, in graph: SemanticGraph, limit: Int = 5) -> [SemanticNode] {
        let queryTerms = Self.terms(query)
        guard !queryTerms.isEmpty else { return [] }
        let ranked = graph.nodes.values.filter { $0.status != .superseded }.map { node in
            (node, queryTerms.intersection(Self.terms(node.claim)).count)
        }.filter { $0.1 > 0 }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            let leftSpecificity = Self.specificity($0.0.kind)
            let rightSpecificity = Self.specificity($1.0.kind)
            if leftSpecificity != rightSpecificity { return leftSpecificity > rightSpecificity }
            if $0.0.confidence != $1.0.confidence { return $0.0.confidence > $1.0.confidence }
            return $0.0.createdAt > $1.0.createdAt
        }
        var claims = Set<String>()
        return ranked.compactMap { node, _ -> SemanticNode? in
            let key = Self.normalizedClaim(node.claim)
            guard claims.insert(key).inserted else { return nil }
            return node
        }.prefix(max(0, limit)).map { $0 }
    }

    private static func terms(_ value: String) -> Set<String> {
        Set(value.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    private static func normalizedClaim(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func specificity(_ kind: SemanticNodeKind) -> Int {
        switch kind {
        case .decision, .intention, .question, .problem, .possibility, .preference: 4
        case .idea, .action, .project, .person, .concept: 3
        case .knowledge, .intent: 2
        case .observation, .context: 1
        }
    }
}
