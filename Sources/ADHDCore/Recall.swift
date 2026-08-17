import Foundation

public enum RecallEvidenceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case capture
    case intention
    case returnPacket
    case correction
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

    public init(
        evidenceID: RecallEvidenceID,
        title: String,
        text: String,
        occurredAt: Date
    ) {
        self.evidenceID = evidenceID
        self.title = title
        self.text = text
        self.occurredAt = occurredAt
    }
}

public struct RecallDocumentSource: Sendable {
    private let repository: any ThoughtRepository

    public init(repository: any ThoughtRepository) {
        self.repository = repository
    }

    public func documents() async throws -> [RecallDocument] {
        async let captures = repository.allCaptures()
        async let intentions = repository.allIntentions()
        async let corrections = repository.transcriptionCorrections()
        var documents = try await captureDocuments(captures)
        documents.append(contentsOf: try await intentionDocuments(intentions))
        documents.append(contentsOf: try await correctionDocuments(corrections))
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

    private static func comesBefore(_ lhs: RecallDocument, _ rhs: RecallDocument) -> Bool {
        if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
        if lhs.evidenceID.kind.rawValue != rhs.evidenceID.kind.rawValue {
            return lhs.evidenceID.kind.rawValue < rhs.evidenceID.kind.rawValue
        }
        return lhs.evidenceID.id.uuidString < rhs.evidenceID.id.uuidString
    }
}
