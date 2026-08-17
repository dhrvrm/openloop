import Foundation

public enum MemoryKind: String, Codable, CaseIterable, Hashable, Sendable {
    case fact
    case decision
    case commitment
    case preference
    case question
    case correction
}

public enum MemoryState: Codable, Equatable, Hashable, Sendable {
    case active
    case contradicted
    case superseded(by: UUID)
    case evidenceExpired
}

public enum EvidenceAvailability: String, Codable, Hashable, Sendable {
    case retained
    case expired
}

public struct MemoryEvidence: Codable, Equatable, Hashable, Sendable {
    public let evidenceID: RecallEvidenceID
    public let excerpt: String
    public let occurredAt: Date
    public var availability: EvidenceAvailability

    public init(
        evidenceID: RecallEvidenceID,
        excerpt: String,
        occurredAt: Date,
        availability: EvidenceAvailability = .retained
    ) {
        self.evidenceID = evidenceID
        self.excerpt = excerpt
        self.occurredAt = occurredAt
        self.availability = availability
    }
}

public enum MemoryRelation: Codable, Equatable, Hashable, Sendable {
    case none
    case supersedes(String)
}

public enum WorkingMemoryError: Error, Equatable, Sendable {
    case emptyStatement
    case statementTooLong
    case invalidConfidence
    case evidenceMissing
    case evidenceExcerptMismatch
}

public struct MemoryCandidate: Codable, Equatable, Sendable {
    public static let maximumStatementLength = 500

    public let kind: MemoryKind
    public let statement: String
    public let evidence: MemoryEvidence
    public let relation: MemoryRelation
    public let confidence: Double

    public init(
        kind: MemoryKind,
        statement: String,
        evidence: MemoryEvidence,
        relation: MemoryRelation = .none,
        confidence: Double = 1
    ) throws {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WorkingMemoryError.emptyStatement }
        guard trimmed.count <= Self.maximumStatementLength else {
            throw WorkingMemoryError.statementTooLong
        }
        guard (0...1).contains(confidence) else { throw WorkingMemoryError.invalidConfidence }

        self.kind = kind
        self.statement = trimmed
        self.evidence = evidence
        self.relation = relation
        self.confidence = confidence
    }
}

public struct MemoryRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var version: Int
    public let kind: MemoryKind
    public let statement: String
    public let confidence: Double
    public var evidence: [MemoryEvidence]
    public var state: MemoryState
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        version: Int = 1,
        kind: MemoryKind,
        statement: String,
        confidence: Double,
        evidence: [MemoryEvidence],
        state: MemoryState = .active,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.version = version
        self.kind = kind
        self.statement = statement
        self.confidence = confidence
        self.evidence = evidence
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MemoryEvidenceValidator: Sendable {
    public init() {}

    public func validate(_ candidate: MemoryCandidate, against documents: [RecallDocument]) throws {
        guard let document = documents.first(where: {
            $0.evidenceID == candidate.evidence.evidenceID
        }) else {
            throw WorkingMemoryError.evidenceMissing
        }
        guard !candidate.evidence.excerpt.isEmpty,
              document.text.contains(candidate.evidence.excerpt) else {
            throw WorkingMemoryError.evidenceExcerptMismatch
        }
    }
}

public struct TemporalMemoryLedger: Sendable {
    public init() {}

    public func applying(
        _ candidate: MemoryCandidate,
        to records: [MemoryRecord],
        at date: Date = Date(),
        id: UUID = UUID()
    ) -> [MemoryRecord] {
        var result = records
        if let index = result.firstIndex(where: {
            $0.kind == candidate.kind
                && Self.normalized($0.statement) == Self.normalized(candidate.statement)
                && Self.isCurrent($0.state)
        }) {
            let evidenceAlreadyExists = result[index].evidence.contains(where: {
                $0.evidenceID == candidate.evidence.evidenceID
                    && $0.excerpt == candidate.evidence.excerpt
            })
            guard !evidenceAlreadyExists else { return result }
            result[index].evidence.append(candidate.evidence)
            result[index].version += 1
            result[index].updatedAt = date
            if result[index].state == .evidenceExpired {
                result[index].state = .active
            }
            return result
        }

        let newRecord = MemoryRecord(
            id: id,
            kind: candidate.kind,
            statement: candidate.statement,
            confidence: candidate.confidence,
            evidence: [candidate.evidence],
            createdAt: date,
            updatedAt: date
        )

        if case let .supersedes(original) = candidate.relation {
            let oldStatement = Self.normalized(original)
            for index in result.indices where
                Self.isCurrent(result[index].state)
                    && Self.normalized(result[index].statement) == oldStatement {
                result[index].state = .superseded(by: id)
                result[index].version += 1
                result[index].updatedAt = date
            }
        }
        result.append(newRecord)
        return result
    }

    public func revalidated(
        _ records: [MemoryRecord],
        against documents: [RecallDocument],
        at date: Date = Date()
    ) -> [MemoryRecord] {
        let documentsByID = Dictionary(uniqueKeysWithValues: documents.map { ($0.evidenceID, $0) })
        return records.map { record in
            var updated = record
            updated.evidence = record.evidence.map { evidence in
                var checked = evidence
                if let document = documentsByID[evidence.evidenceID],
                   document.text.contains(evidence.excerpt) {
                    checked.availability = .retained
                } else {
                    checked.availability = .expired
                }
                return checked
            }

            let previousState = updated.state
            switch previousState {
            case .superseded, .contradicted:
                break
            case .active, .evidenceExpired:
                updated.state = updated.evidence.contains(where: { $0.availability == .retained })
                    ? .active
                    : .evidenceExpired
            }
            if updated.state != previousState || updated.evidence != record.evidence {
                updated.updatedAt = date
            }
            return updated
        }
    }

    public static func normalized(_ statement: String) -> String {
        let folded = statement
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let sanitized = String(folded
            .unicodeScalars
            .map { scalar -> Character in
                CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
            })
        return sanitized
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
    }

    private static func isCurrent(_ state: MemoryState) -> Bool {
        switch state {
        case .active, .contradicted, .evidenceExpired: true
        case .superseded: false
        }
    }
}

public protocol MemoryExtractionProvider: Sendable {
    func candidates(from documents: [RecallDocument]) async throws -> [MemoryCandidate]
}

public protocol WorkingMemoryCompiling: Sendable {
    func compile() async throws -> [MemoryRecord]
}

public struct WorkingMemoryCompiler: WorkingMemoryCompiling, Sendable {
    private let source: any RecallDocumentProviding
    private let provider: any MemoryExtractionProvider
    private let repository: any ThoughtRepository
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        source: any RecallDocumentProviding,
        provider: any MemoryExtractionProvider,
        repository: any ThoughtRepository,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.source = source
        self.provider = provider
        self.repository = repository
        self.now = now
        self.makeID = makeID
    }

    public func compile() async throws -> [MemoryRecord] {
        async let sourceDocuments = source.documents()
        async let storedRecords = repository.memoryRecords()
        let (documents, existing) = try await (sourceDocuments, storedRecords)
        let candidates = try await provider.candidates(from: documents)
        var records = existing
        var consumedEvidence = Set(existing.flatMap { $0.evidence.map(\.evidenceID) })
        let validator = MemoryEvidenceValidator()
        let ledger = TemporalMemoryLedger()

        for candidate in candidates where !consumedEvidence.contains(candidate.evidence.evidenceID) {
            try validator.validate(candidate, against: documents)
            records = ledger.applying(
                candidate,
                to: records,
                at: now(),
                id: makeID()
            )
            consumedEvidence.insert(candidate.evidence.evidenceID)
        }
        records = ledger.revalidated(records, against: documents, at: now())
        try await repository.save(memoryRecords: records)
        return Self.sorted(records)
    }

    private static func sorted(_ records: [MemoryRecord]) -> [MemoryRecord] {
        records.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

/// A deliberately conservative extractor: only explicit user markers and recorded
/// transcription corrections may become durable working memory.
public struct DeterministicMemoryExtractionProvider: MemoryExtractionProvider, Sendable {
    public init() {}

    public func candidates(from documents: [RecallDocument]) async throws -> [MemoryCandidate] {
        try documents.compactMap(candidate)
    }

    private func candidate(from document: RecallDocument) throws -> MemoryCandidate? {
        let evidence = MemoryEvidence(
            evidenceID: document.evidenceID,
            excerpt: document.text,
            occurredAt: document.occurredAt
        )

        if document.evidenceID.kind == .correction {
            let parts = document.text
                .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            return try MemoryCandidate(
                kind: .correction,
                statement: parts[0],
                evidence: evidence,
                relation: .supersedes(parts[1])
            )
        }

        guard document.evidenceID.kind != .memory else { return nil }
        let text = document.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let correction = correctionParts(from: text) {
            return try MemoryCandidate(
                kind: .correction,
                statement: correction.replacement,
                evidence: evidence,
                relation: .supersedes(correction.original)
            )
        }

        let markers: [(prefix: String, kind: MemoryKind)] = [
            ("decision:", .decision),
            ("commitment:", .commitment),
            ("promise:", .commitment),
            ("preference:", .preference),
            ("prefer:", .preference),
            ("question:", .question),
            ("remember:", .fact),
        ]

        for marker in markers where text.lowercased().hasPrefix(marker.prefix) {
            let statement = String(text.dropFirst(marker.prefix.count))
            return try MemoryCandidate(kind: marker.kind, statement: statement, evidence: evidence)
        }
        return nil
    }

    private func correctionParts(from text: String) -> (original: String, replacement: String)? {
        let prefix = "correction:"
        guard text.lowercased().hasPrefix(prefix) else { return nil }
        let body = String(text.dropFirst(prefix.count))
        let pieces = body.components(separatedBy: "->")
        guard pieces.count == 2 else { return nil }
        let original = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, !replacement.isEmpty else { return nil }
        return (original, replacement)
    }
}
