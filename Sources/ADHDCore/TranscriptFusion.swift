import Foundation

public enum TranscriptFusionReason: String, Codable, Equatable, Sendable {
    case exactAgreement
    case primaryOnly
    case lowConfidence
    case languageSwitch
    case domainTermMissing
    case recognizerDisagreement
    case secondaryEvidenceMissing
}

public enum TranscriptFusionResolution: String, Codable, Equatable, Sendable {
    case exactAgreement
    case primaryAccepted
    case reviewRequired
}

public struct TranscriptEvidence: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let engineIdentifier: String
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let confidence: Double?
    public let detectedLanguage: String?

    public init(
        id: UUID = UUID(),
        engineIdentifier: String,
        text: String,
        start: TimeInterval,
        end: TimeInterval,
        confidence: Double? = nil,
        detectedLanguage: String? = nil
    ) {
        self.id = id
        self.engineIdentifier = engineIdentifier
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.start = start
        self.end = end
        self.confidence = confidence.map { min(1, max(0, $0.isFinite ? $0 : 0)) }
        self.detectedLanguage = detectedLanguage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct FusedTranscriptSpan: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let primary: TranscriptEvidence
    public let secondary: TranscriptEvidence?
    public let selectedText: String
    public let resolution: TranscriptFusionResolution
    public let reasons: [TranscriptFusionReason]

    public init(
        id: UUID = UUID(),
        primary: TranscriptEvidence,
        secondary: TranscriptEvidence?,
        selectedText: String,
        resolution: TranscriptFusionResolution,
        reasons: [TranscriptFusionReason]
    ) {
        self.id = id
        self.primary = primary
        self.secondary = secondary
        self.selectedText = selectedText
        self.resolution = resolution
        self.reasons = reasons
    }
}

public struct TranscriptFusionResult: Codable, Equatable, Sendable {
    public let spans: [FusedTranscriptSpan]

    public init(spans: [FusedTranscriptSpan]) {
        self.spans = spans.sorted {
            if $0.primary.start == $1.primary.start {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.primary.start < $1.primary.start
        }
    }

    public var selectedText: String {
        spans.map(\.selectedText).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    public var reviewSpans: [FusedTranscriptSpan] {
        spans.filter { $0.resolution == .reviewRequired }
    }
}

public struct TranscriptFusionPolicy: Equatable, Sendable {
    public let lowConfidenceThreshold: Double

    public init(lowConfidenceThreshold: Double = 0.72) {
        self.lowConfidenceThreshold = lowConfidenceThreshold
    }

    public func reasonsToRequestSecondary(
        for evidence: TranscriptEvidence,
        expectedDomainTerms: [String]
    ) -> [TranscriptFusionReason] {
        var reasons: [TranscriptFusionReason] = []
        if let confidence = evidence.confidence, confidence < lowConfidenceThreshold {
            reasons.append(.lowConfidence)
        }
        if Self.containsLatin(evidence.text), Self.containsDevanagari(evidence.text) {
            reasons.append(.languageSwitch)
        }
        if expectedDomainTerms.contains(where: { !Self.containsPhrase($0, in: evidence.text) }) {
            reasons.append(.domainTermMissing)
        }
        return reasons
    }

    public func fuse(
        primary: [TranscriptEvidence],
        secondary: [TranscriptEvidence],
        expectedDomainTerms: [String] = []
    ) -> TranscriptFusionResult {
        var unusedSecondary = secondary
        let spans = primary.map { primaryEvidence -> FusedTranscriptSpan in
            let escalationReasons = reasonsToRequestSecondary(
                for: primaryEvidence,
                expectedDomainTerms: expectedDomainTerms
            )
            let secondaryIndex = Self.bestMatchIndex(
                for: primaryEvidence,
                candidates: unusedSecondary
            )
            let secondaryEvidence = secondaryIndex.map { unusedSecondary.remove(at: $0) }

            guard let secondaryEvidence else {
                let needsReview = !escalationReasons.isEmpty
                return FusedTranscriptSpan(
                    primary: primaryEvidence,
                    secondary: nil,
                    selectedText: primaryEvidence.text,
                    resolution: needsReview ? .reviewRequired : .primaryAccepted,
                    reasons: needsReview
                        ? escalationReasons + [.secondaryEvidenceMissing]
                        : [.primaryOnly]
                )
            }
            if Self.normalized(primaryEvidence.text) == Self.normalized(secondaryEvidence.text) {
                return FusedTranscriptSpan(
                    primary: primaryEvidence,
                    secondary: secondaryEvidence,
                    selectedText: primaryEvidence.text,
                    resolution: .exactAgreement,
                    reasons: [.exactAgreement]
                )
            }
            return FusedTranscriptSpan(
                primary: primaryEvidence,
                secondary: secondaryEvidence,
                selectedText: primaryEvidence.text,
                resolution: .reviewRequired,
                reasons: escalationReasons + [.recognizerDisagreement]
            )
        }
        return TranscriptFusionResult(spans: spans)
    }

    private static func bestMatchIndex(
        for primary: TranscriptEvidence,
        candidates: [TranscriptEvidence]
    ) -> Int? {
        candidates.indices.max { lhs, rhs in
            overlap(primary, candidates[lhs]) < overlap(primary, candidates[rhs])
        }.flatMap { overlap(primary, candidates[$0]) > 0 ? $0 : nil }
    }

    private static func overlap(_ lhs: TranscriptEvidence, _ rhs: TranscriptEvidence) -> Double {
        max(0, min(lhs.end, rhs.end) - max(lhs.start, rhs.start))
    }

    private static func normalized(_ text: String) -> String {
        var tokens: [String] = []
        var token = ""
        for character in text {
            if character.isLetter || character.isNumber {
                token.append(character)
            } else if !token.isEmpty {
                tokens.append(token.lowercased())
                token = ""
            }
        }
        if !token.isEmpty { tokens.append(token.lowercased()) }
        return tokens.joined(separator: " ")
    }

    private static func containsPhrase(_ phrase: String, in text: String) -> Bool {
        let phrase = normalized(phrase)
        guard !phrase.isEmpty else { return true }
        return normalized(text).contains(phrase)
    }

    private static func containsLatin(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x0041...0x005A).contains($0.value) || (0x0061...0x007A).contains($0.value)
        }
    }

    private static func containsDevanagari(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
    }
}
