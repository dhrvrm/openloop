import Foundation

public enum RecallEvidenceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case capture
    case intention
    case returnPacket
    case correction
    case memory
    case meetingTranscript
}

public struct RecallEvidenceID: Codable, Equatable, Hashable, Sendable {
    public let kind: RecallEvidenceKind
    public let id: UUID

    public init(kind: RecallEvidenceKind, id: UUID) {
        self.kind = kind
        self.id = id
    }
}

public struct RecallDocument: Codable, Equatable, Identifiable, Sendable {
    public var id: RecallEvidenceID { evidenceID }
    public let evidenceID: RecallEvidenceID
    public let title: String
    public let text: String
    public let occurredAt: Date
    public let memoryState: MemoryState?

    public init(
        evidenceID: RecallEvidenceID,
        title: String,
        text: String,
        occurredAt: Date,
        memoryState: MemoryState? = nil
    ) {
        self.evidenceID = evidenceID
        self.title = title
        self.text = text
        self.occurredAt = occurredAt
        self.memoryState = memoryState
    }
}

public protocol RecallDocumentProviding: Sendable {
    func documents() async throws -> [RecallDocument]
}

public struct RecallDocumentSource: RecallDocumentProviding, Sendable {
    private let repository: any ThoughtRepository

    public init(repository: any ThoughtRepository) {
        self.repository = repository
    }

    public func documents() async throws -> [RecallDocument] {
        async let captures = repository.allCaptures()
        async let intentions = repository.allIntentions()
        async let corrections = repository.transcriptionCorrections()
        async let memories = repository.memoryRecords()
        var documents = try await captureDocuments(captures)
        documents.append(contentsOf: try await intentionDocuments(intentions))
        documents.append(contentsOf: try await correctionDocuments(corrections))
        documents.append(contentsOf: try await memoryDocuments(memories))
        return documents.sorted(by: Self.comesBefore)
    }

    private func captureDocuments(_ captures: [RawCapture]) -> [RecallDocument] {
        captures.map { capture in
            RecallDocument(
                evidenceID: RecallEvidenceID(kind: .capture, id: capture.id),
                title: capture.source == .voice ? "Voice capture" : "Capture",
                text: capture.text,
                occurredAt: capture.createdAt
            )
        }
    }

    private func intentionDocuments(_ intentions: [Intention]) -> [RecallDocument] {
        intentions.flatMap { intention -> [RecallDocument] in
            var result = [RecallDocument(
                evidenceID: RecallEvidenceID(kind: .intention, id: intention.id),
                title: intention.desiredOutcome,
                text: [
                    intention.desiredOutcome,
                    intention.nextAction,
                    intention.state.rawValue,
                ].joined(separator: "\n"),
                occurredAt: intention.createdAt
            )]
            if let packet = intention.returnPacket {
                let parts = [packet.justCompleted, packet.nextAction, packet.blocker]
                    .compactMap { $0 }
                    + packet.references
                result.append(RecallDocument(
                    evidenceID: RecallEvidenceID(kind: .returnPacket, id: intention.id),
                    title: "Return to \(intention.desiredOutcome)",
                    text: parts.joined(separator: "\n"),
                    occurredAt: packet.capturedAt
                ))
            }
            return result
        }
    }

    private func correctionDocuments(
        _ corrections: [TranscriptionCorrection]
    ) -> [RecallDocument] {
        corrections.map { correction in
            RecallDocument(
                evidenceID: RecallEvidenceID(kind: .correction, id: correction.id),
                title: "Voice correction",
                text: [correction.corrected, correction.recognized].joined(separator: "\n"),
                occurredAt: correction.createdAt
            )
        }
    }

    private func memoryDocuments(_ records: [MemoryRecord]) -> [RecallDocument] {
        records.map { record in
            RecallDocument(
                evidenceID: RecallEvidenceID(kind: .memory, id: record.id),
                title: Self.memoryTitle(record),
                text: ([record.statement] + record.evidence.map(\.excerpt)).joined(separator: "\n"),
                occurredAt: record.updatedAt,
                memoryState: record.state
            )
        }
    }

    private static func memoryTitle(_ record: MemoryRecord) -> String {
        let kind = record.kind.rawValue.capitalized
        return switch record.state {
        case .active: "\(kind) · Current memory"
        case .contradicted: "\(kind) · Contradicted memory"
        case .superseded: "\(kind) · Superseded memory"
        case .evidenceExpired: "\(kind) · Evidence expired"
        }
    }

    private static func comesBefore(_ lhs: RecallDocument, _ rhs: RecallDocument) -> Bool {
        if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
        if lhs.evidenceID.kind.rawValue != rhs.evidenceID.kind.rawValue {
            return lhs.evidenceID.kind.rawValue < rhs.evidenceID.kind.rawValue
        }
        return lhs.evidenceID.id.uuidString < rhs.evidenceID.id.uuidString
    }
}

public struct RecallQuery: Equatable, Sendable {
    public let text: String
    public let limit: Int

    public init(text: String, limit: Int = 5) {
        self.text = text
        self.limit = max(1, min(limit, 50))
    }
}

public enum RecallContributionKind: String, Codable, Equatable, Hashable, Sendable {
    case exactPhrase
    case tokenCoverage
    case semanticSimilarity
}

public struct RecallContribution: Codable, Equatable, Identifiable, Sendable {
    public var id: RecallContributionKind { kind }
    public let kind: RecallContributionKind
    public let value: Double

    public init(kind: RecallContributionKind, value: Double) {
        self.kind = kind
        self.value = value
    }
}

public struct RecallHit: Equatable, Identifiable, Sendable {
    public var id: RecallEvidenceID { evidenceID }
    public let evidenceID: RecallEvidenceID
    public let title: String
    public let excerpt: String
    public let occurredAt: Date
    public let score: Double
    public let contributions: [RecallContribution]

    public init(
        evidenceID: RecallEvidenceID,
        title: String,
        excerpt: String,
        occurredAt: Date,
        score: Double,
        contributions: [RecallContribution]
    ) {
        self.evidenceID = evidenceID
        self.title = title
        self.excerpt = excerpt
        self.occurredAt = occurredAt
        self.score = score
        self.contributions = contributions
    }
}

public struct RecallResult: Equatable, Sendable {
    public let query: String
    public let hits: [RecallHit]

    public init(query: String, hits: [RecallHit]) {
        self.query = query
        self.hits = hits
    }
}

public enum RecallError: Error, Equatable {
    case emptyQuery
    case embeddingUnavailable
    case invalidEmbeddingCount
}

public protocol EmbeddingProvider: Sendable {
    var identifier: String { get async }
    func vectors(for texts: [String]) async throws -> [[Double]]
}

public struct RecallIndexSnapshot: Codable, Equatable, Sendable {
    public let providerIdentifier: String
    public let documents: [RecallDocument]
    public let vectors: [[Double]]

    public init(
        providerIdentifier: String,
        documents: [RecallDocument],
        vectors: [[Double]]
    ) {
        self.providerIdentifier = providerIdentifier
        self.documents = documents
        self.vectors = vectors
    }
}

public protocol RecallIndexStore: Sendable {
    func load() async throws -> RecallIndexSnapshot?
    func save(_ snapshot: RecallIndexSnapshot) async throws
    func discard() async throws
}

public protocol RecallSearching: Sendable {
    func retrieve(_ query: RecallQuery) async throws -> RecallResult
}

public struct RecallLoop: RecallSearching, Sendable {
    private let source: any RecallDocumentProviding
    private let indexStore: any RecallIndexStore
    private let embeddingProvider: any EmbeddingProvider

    public init(
        source: any RecallDocumentProviding,
        indexStore: any RecallIndexStore,
        embeddingProvider: any EmbeddingProvider
    ) {
        self.source = source
        self.indexStore = indexStore
        self.embeddingProvider = embeddingProvider
    }

    public func retrieve(_ query: RecallQuery) async throws -> RecallResult {
        let normalizedQuery = Self.normalized(query.text)
        guard !normalizedQuery.isEmpty else { throw RecallError.emptyQuery }
        let documents = try await source.documents()
        let semantic = await semanticValues(query: normalizedQuery, documents: documents)
        let queryTokens = Set(Self.tokens(query.text))

        let hits = documents.enumerated().compactMap { index, document -> RecallHit? in
            let normalizedDocument = Self.normalized(document.text)
            let documentTokens = Set(Self.tokens(document.text))
            let exact = normalizedDocument.contains(normalizedQuery)
            let coverage = queryTokens.isEmpty ? 0 : Double(
                queryTokens.intersection(documentTokens).count
            ) / Double(queryTokens.count)
            let lexical = exact ? 1.0 : coverage
            let semanticValue = semantic.flatMap { values in
                values.indices.contains(index) ? values[index] : nil
            }
            guard lexical > 0 || (semanticValue ?? 0) >= 0.55 else { return nil }

            var contributions: [RecallContribution] = []
            if exact {
                contributions.append(RecallContribution(kind: .exactPhrase, value: 1))
            }
            if coverage > 0 {
                contributions.append(RecallContribution(kind: .tokenCoverage, value: coverage))
            }
            if let semanticValue {
                contributions.append(RecallContribution(
                    kind: .semanticSimilarity,
                    value: semanticValue
                ))
            }
            let baseScore = semanticValue.map { 0.65 * lexical + 0.35 * $0 } ?? lexical
            let score = baseScore * Self.memoryMultiplier(document.memoryState)
            return RecallHit(
                evidenceID: document.evidenceID,
                title: document.title,
                excerpt: document.text,
                occurredAt: document.occurredAt,
                score: score,
                contributions: contributions
            )
        }.sorted(by: Self.hitComesBefore)

        return RecallResult(query: query.text.trimmingCharacters(in: .whitespacesAndNewlines), hits: Array(hits.prefix(query.limit)))
    }

    private func semanticValues(
        query: String,
        documents: [RecallDocument]
    ) async -> [Double]? {
        do {
            let identifier = await embeddingProvider.identifier
            let documentVectors: [[Double]]
            if let snapshot = try await indexStore.load(),
               snapshot.providerIdentifier == identifier,
               snapshot.documents == documents,
               snapshot.vectors.count == documents.count {
                documentVectors = snapshot.vectors
            } else {
                documentVectors = try await embeddingProvider.vectors(
                    for: documents.map(\.text)
                )
                guard documentVectors.count == documents.count else {
                    throw RecallError.invalidEmbeddingCount
                }
                try await indexStore.save(RecallIndexSnapshot(
                    providerIdentifier: identifier,
                    documents: documents,
                    vectors: documentVectors
                ))
            }
            guard let queryVector = try await embeddingProvider.vectors(for: [query]).first else {
                throw RecallError.invalidEmbeddingCount
            }
            return documentVectors.map { Self.cosineSimilarity($0, queryVector) }
        } catch {
            return nil
        }
    }

    private static func normalized(_ text: String) -> String {
        tokens(text).joined(separator: " ")
    }

    private static func tokens(_ text: String) -> [String] {
        var values: [String] = []
        var token = ""
        for character in text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ) {
            if character.isLetter || character.isNumber {
                token.append(character)
            } else if !token.isEmpty {
                values.append(token)
                token = ""
            }
        }
        if !token.isEmpty { values.append(token) }
        return values
    }

    private static func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return 0 }
        let dot = zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
        let leftMagnitude = sqrt(lhs.reduce(0) { $0 + $1 * $1 })
        let rightMagnitude = sqrt(rhs.reduce(0) { $0 + $1 * $1 })
        guard leftMagnitude > 0, rightMagnitude > 0 else { return 0 }
        let cosine = dot / (leftMagnitude * rightMagnitude)
        return min(1, max(0, (cosine + 1) / 2))
    }

    private static func hitComesBefore(_ lhs: RecallHit, _ rhs: RecallHit) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt > rhs.occurredAt }
        if lhs.evidenceID.kind.rawValue != rhs.evidenceID.kind.rawValue {
            return lhs.evidenceID.kind.rawValue < rhs.evidenceID.kind.rawValue
        }
        return lhs.evidenceID.id.uuidString < rhs.evidenceID.id.uuidString
    }

    private static func memoryMultiplier(_ state: MemoryState?) -> Double {
        switch state {
        case nil, .active: 1
        case .contradicted: 0.85
        case .superseded: 0.55
        case .evidenceExpired: 0.4
        }
    }
}

public struct RecallEvaluationCase: Codable, Equatable, Sendable {
    public let query: String
    public let expectedEvidence: [RecallEvidenceID]
    public let exact: Bool

    public init(query: String, expectedEvidence: [RecallEvidenceID], exact: Bool) {
        self.query = query
        self.expectedEvidence = expectedEvidence
        self.exact = exact
    }
}

public struct RecallEvaluationFixture: Codable, Equatable, Sendable {
    public let documents: [RecallDocument]
    public let cases: [RecallEvaluationCase]
    public let vectors: [String: [Double]]

    public init(
        documents: [RecallDocument],
        cases: [RecallEvaluationCase],
        vectors: [String: [Double]]
    ) {
        self.documents = documents
        self.cases = cases
        self.vectors = vectors
    }
}

public struct RecallEvaluationReport: Equatable, Sendable {
    public let caseCount: Int
    public let topFiveHitRate: Double?
    public let exactSearchP95Milliseconds: Double?

    public init(
        cases: [RecallEvaluationCase],
        results: [RecallResult],
        latenciesMilliseconds: [Double]
    ) {
        caseCount = cases.count
        guard !cases.isEmpty, cases.count == results.count else {
            topFiveHitRate = nil
            exactSearchP95Milliseconds = nil
            return
        }
        let matches = zip(cases, results).filter { evaluation, result in
            let returned = Set(result.hits.prefix(5).map(\.evidenceID))
            return evaluation.expectedEvidence.contains { returned.contains($0) }
        }.count
        topFiveHitRate = Double(matches) / Double(cases.count)
        let exactLatencies = zip(cases, latenciesMilliseconds).compactMap {
            $0.0.exact ? $0.1 : nil
        }.sorted()
        if exactLatencies.isEmpty {
            exactSearchP95Milliseconds = nil
        } else {
            let rank = max(1, Int(ceil(0.95 * Double(exactLatencies.count))))
            exactSearchP95Milliseconds = exactLatencies[rank - 1]
        }
    }
}
