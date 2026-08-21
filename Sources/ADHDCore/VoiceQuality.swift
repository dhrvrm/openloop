import Foundation

public enum VoiceQualityEvidenceError: Error, Equatable {
    case emptySourceAudioIdentifier
    case emptyReferenceTranscript
    case emptyLanguageSequence
    case invalidLanguageIdentifier
    case invalidDomainTerm
    case emptyEngineIdentifier
    case invalidLatency
}

public enum VoiceQualityRepositoryError: Error, Equatable {
    case missingCase(UUID)
}

/// Immutable ground truth for one retained, user-approved audio example.
public struct VoiceQualityCase: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sourceAudioIdentifier: String
    public let referenceTranscript: String
    public let languageSequence: [String]
    public let domainTerms: [String]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sourceAudioIdentifier: String,
        referenceTranscript: String,
        languageSequence: [String],
        domainTerms: [String] = [],
        createdAt: Date = .now
    ) throws {
        let source = sourceAudioIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = referenceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let languages = languageSequence.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let terms = domainTerms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard !source.isEmpty else { throw VoiceQualityEvidenceError.emptySourceAudioIdentifier }
        guard !reference.isEmpty else { throw VoiceQualityEvidenceError.emptyReferenceTranscript }
        guard !languages.isEmpty else { throw VoiceQualityEvidenceError.emptyLanguageSequence }
        guard languages.allSatisfy({ !$0.isEmpty }) else {
            throw VoiceQualityEvidenceError.invalidLanguageIdentifier
        }
        guard terms.allSatisfy({ !$0.isEmpty }) else {
            throw VoiceQualityEvidenceError.invalidDomainTerm
        }

        self.id = id
        self.sourceAudioIdentifier = source
        self.referenceTranscript = reference
        self.languageSequence = languages
        self.domainTerms = Self.uniqued(terms)
        self.createdAt = createdAt
    }

    private static func uniqued(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            seen.insert(value.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )).inserted
        }
    }
}

/// One engine's immutable output for a quality case. Empty output is valid evidence.
public struct VoiceQualityAttempt: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let caseID: UUID
    public let engineIdentifier: String
    public let hypothesis: String
    public let firstPartialMilliseconds: Double?
    public let stopToFinalMilliseconds: Double
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        caseID: UUID,
        engineIdentifier: String,
        hypothesis: String,
        firstPartialMilliseconds: Double? = nil,
        stopToFinalMilliseconds: Double,
        createdAt: Date = .now
    ) throws {
        let engine = engineIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !engine.isEmpty else { throw VoiceQualityEvidenceError.emptyEngineIdentifier }
        guard stopToFinalMilliseconds.isFinite, stopToFinalMilliseconds >= 0 else {
            throw VoiceQualityEvidenceError.invalidLatency
        }
        if let firstPartialMilliseconds {
            guard firstPartialMilliseconds.isFinite, firstPartialMilliseconds >= 0 else {
                throw VoiceQualityEvidenceError.invalidLatency
            }
        }

        self.id = id
        self.caseID = caseID
        self.engineIdentifier = engine
        self.hypothesis = hypothesis.trimmingCharacters(in: .whitespacesAndNewlines)
        self.firstPartialMilliseconds = firstPartialMilliseconds
        self.stopToFinalMilliseconds = stopToFinalMilliseconds
        self.createdAt = createdAt
    }
}

public struct VoiceQualityMetrics: Equatable, Sendable {
    public let referenceWordCount: Int
    public let wordEditCount: Int
    public let wordErrorRate: Double
    public let referenceDevanagariCharacterCount: Int
    public let devanagariCharacterEditCount: Int
    public let devanagariCharacterErrorRate: Double?
    public let expectedDomainTermCount: Int
    public let recognizedDomainTermCount: Int
    public let domainTermRecall: Double?
    public let droppedReferenceTokenCount: Int
    public let droppedSpanRate: Double

    public init(qualityCase: VoiceQualityCase, attempt: VoiceQualityAttempt) {
        let referenceTokens = VoiceQualityText.tokens(in: qualityCase.referenceTranscript)
        let hypothesisTokens = VoiceQualityText.tokens(in: attempt.hypothesis)
        let wordEdits = VoiceQualityText.editDistance(from: referenceTokens, to: hypothesisTokens)
        let sharedTokens = VoiceQualityText.longestCommonSubsequenceLength(
            referenceTokens,
            hypothesisTokens
        )
        let referenceDevanagari = VoiceQualityText.devanagariCharacters(
            in: qualityCase.referenceTranscript
        )
        let hypothesisDevanagari = VoiceQualityText.devanagariCharacters(in: attempt.hypothesis)
        let devanagariEdits = VoiceQualityText.editDistance(
            from: referenceDevanagari,
            to: hypothesisDevanagari
        )
        let recognizedTerms = qualityCase.domainTerms.filter {
            VoiceQualityText.containsPhrase($0, in: hypothesisTokens)
        }.count

        referenceWordCount = referenceTokens.count
        wordEditCount = wordEdits
        wordErrorRate = Self.rate(errors: wordEdits, referenceCount: referenceTokens.count)
        referenceDevanagariCharacterCount = referenceDevanagari.count
        devanagariCharacterEditCount = devanagariEdits
        devanagariCharacterErrorRate = referenceDevanagari.isEmpty
            ? nil
            : Double(devanagariEdits) / Double(referenceDevanagari.count)
        expectedDomainTermCount = qualityCase.domainTerms.count
        recognizedDomainTermCount = recognizedTerms
        domainTermRecall = qualityCase.domainTerms.isEmpty
            ? nil
            : Double(recognizedTerms) / Double(qualityCase.domainTerms.count)
        droppedReferenceTokenCount = max(0, referenceTokens.count - sharedTokens)
        droppedSpanRate = referenceTokens.isEmpty
            ? 0
            : Double(droppedReferenceTokenCount) / Double(referenceTokens.count)
    }

    private static func rate(errors: Int, referenceCount: Int) -> Double {
        guard referenceCount > 0 else { return errors == 0 ? 0 : 1 }
        return Double(errors) / Double(referenceCount)
    }
}

public struct VoiceQualityEvaluation: Equatable, Sendable {
    public let qualityCase: VoiceQualityCase
    public let attempt: VoiceQualityAttempt
    public let metrics: VoiceQualityMetrics

    public init(qualityCase: VoiceQualityCase, attempt: VoiceQualityAttempt) {
        self.qualityCase = qualityCase
        self.attempt = attempt
        metrics = VoiceQualityMetrics(qualityCase: qualityCase, attempt: attempt)
    }
}

public struct VoiceQualityReport: Equatable, Sendable {
    public let caseCount: Int
    public let attemptCount: Int
    public let wordErrorRate: Double?
    public let devanagariCharacterErrorRate: Double?
    public let domainTermRecall: Double?
    public let droppedSpanRate: Double?
    public let firstPartialP95Milliseconds: Double?
    public let stopToFinalP95Milliseconds: Double?

    public init(evaluations: [VoiceQualityEvaluation]) {
        let metrics = evaluations.map(\.metrics)
        caseCount = Set(evaluations.map { $0.qualityCase.id }).count
        attemptCount = evaluations.count
        wordErrorRate = Self.errorRate(
            errors: metrics.reduce(0) { $0 + $1.wordEditCount },
            references: metrics.reduce(0) { $0 + $1.referenceWordCount },
            hasSamples: !metrics.isEmpty
        )
        devanagariCharacterErrorRate = Self.errorRate(
            errors: metrics.reduce(0) { $0 + $1.devanagariCharacterEditCount },
            references: metrics.reduce(0) { $0 + $1.referenceDevanagariCharacterCount },
            hasSamples: metrics.contains { $0.referenceDevanagariCharacterCount > 0 }
        )
        let expectedTerms = metrics.reduce(0) { $0 + $1.expectedDomainTermCount }
        domainTermRecall = expectedTerms == 0 ? nil : Double(
            metrics.reduce(0) { $0 + $1.recognizedDomainTermCount }
        ) / Double(expectedTerms)
        let referenceWords = metrics.reduce(0) { $0 + $1.referenceWordCount }
        droppedSpanRate = metrics.isEmpty ? nil : (
            referenceWords == 0 ? 0 : Double(
                metrics.reduce(0) { $0 + $1.droppedReferenceTokenCount }
            ) / Double(referenceWords)
        )
        firstPartialP95Milliseconds = Self.nearestRankP95(
            evaluations.compactMap { $0.attempt.firstPartialMilliseconds }
        )
        stopToFinalP95Milliseconds = Self.nearestRankP95(
            evaluations.map { $0.attempt.stopToFinalMilliseconds }
        )
    }

    private static func errorRate(errors: Int, references: Int, hasSamples: Bool) -> Double? {
        guard hasSamples else { return nil }
        guard references > 0 else { return errors == 0 ? 0 : 1 }
        return Double(errors) / Double(references)
    }

    private static func nearestRankP95(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(0.95 * Double(sorted.count))))
        return sorted[rank - 1]
    }
}

public enum VoiceQualityGateViolation: Equatable, Sendable {
    case noEvidence
    case wordErrorRate(actual: Double, maximum: Double)
    case devanagariCharacterErrorRate(actual: Double, maximum: Double)
    case domainTermRecall(actual: Double, minimum: Double)
    case droppedSpanRate(actual: Double, maximum: Double)
    case stopToFinalP95Milliseconds(actual: Double, maximum: Double)
}

public struct VoiceQualityGate: Equatable, Sendable {
    public let maximumWordErrorRate: Double
    public let maximumDevanagariCharacterErrorRate: Double
    public let minimumDomainTermRecall: Double
    public let maximumDroppedSpanRate: Double
    public let maximumStopToFinalP95Milliseconds: Double

    public init(
        maximumWordErrorRate: Double = 0.12,
        maximumDevanagariCharacterErrorRate: Double = 0.08,
        minimumDomainTermRecall: Double = 0.95,
        maximumDroppedSpanRate: Double = 0.04,
        maximumStopToFinalP95Milliseconds: Double = 1_500
    ) {
        self.maximumWordErrorRate = maximumWordErrorRate
        self.maximumDevanagariCharacterErrorRate = maximumDevanagariCharacterErrorRate
        self.minimumDomainTermRecall = minimumDomainTermRecall
        self.maximumDroppedSpanRate = maximumDroppedSpanRate
        self.maximumStopToFinalP95Milliseconds = maximumStopToFinalP95Milliseconds
    }

    public func violations(in report: VoiceQualityReport) -> [VoiceQualityGateViolation] {
        guard report.attemptCount > 0 else { return [.noEvidence] }
        var result: [VoiceQualityGateViolation] = []
        if let actual = report.wordErrorRate, actual > maximumWordErrorRate {
            result.append(.wordErrorRate(actual: actual, maximum: maximumWordErrorRate))
        }
        if let actual = report.devanagariCharacterErrorRate,
           actual > maximumDevanagariCharacterErrorRate {
            result.append(.devanagariCharacterErrorRate(
                actual: actual,
                maximum: maximumDevanagariCharacterErrorRate
            ))
        }
        if let actual = report.domainTermRecall, actual < minimumDomainTermRecall {
            result.append(.domainTermRecall(actual: actual, minimum: minimumDomainTermRecall))
        }
        if let actual = report.droppedSpanRate, actual > maximumDroppedSpanRate {
            result.append(.droppedSpanRate(actual: actual, maximum: maximumDroppedSpanRate))
        }
        if let actual = report.stopToFinalP95Milliseconds,
           actual > maximumStopToFinalP95Milliseconds {
            result.append(.stopToFinalP95Milliseconds(
                actual: actual,
                maximum: maximumStopToFinalP95Milliseconds
            ))
        }
        return result
    }

    public func passes(_ report: VoiceQualityReport) -> Bool {
        violations(in: report).isEmpty
    }
}

private enum VoiceQualityText {
    static func tokens(in text: String) -> [String] {
        var result: [String] = []
        var token = ""
        for character in text {
            if character.isLetter || character.isNumber {
                token.append(character)
            } else if !token.isEmpty {
                result.append(normalize(token))
                token = ""
            }
        }
        if !token.isEmpty { result.append(normalize(token)) }
        return result
    }

    static func devanagariCharacters(in text: String) -> [Unicode.Scalar] {
        text.unicodeScalars.filter {
            (0x0900...0x097F).contains($0.value) || (0xA8E0...0xA8FF).contains($0.value)
        }
    }

    static func containsPhrase(_ phrase: String, in tokens: [String]) -> Bool {
        let phraseTokens = self.tokens(in: phrase)
        guard !phraseTokens.isEmpty, phraseTokens.count <= tokens.count else { return false }
        for start in 0...(tokens.count - phraseTokens.count) {
            if Array(tokens[start..<(start + phraseTokens.count)]) == phraseTokens { return true }
        }
        return false
    }

    static func editDistance<Element: Equatable>(from source: [Element], to target: [Element]) -> Int {
        guard !source.isEmpty else { return target.count }
        guard !target.isEmpty else { return source.count }
        var previous = Array(0...target.count)
        var current = Array(repeating: 0, count: target.count + 1)
        for sourceIndex in source.indices {
            current[0] = sourceIndex + 1
            for targetIndex in target.indices {
                let substitution = previous[targetIndex]
                    + (source[sourceIndex] == target[targetIndex] ? 0 : 1)
                current[targetIndex + 1] = min(
                    previous[targetIndex + 1] + 1,
                    current[targetIndex] + 1,
                    substitution
                )
            }
            swap(&previous, &current)
        }
        return previous[target.count]
    }

    static func longestCommonSubsequenceLength<Element: Equatable>(
        _ source: [Element],
        _ target: [Element]
    ) -> Int {
        guard !source.isEmpty, !target.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: target.count + 1)
        var current = previous
        for sourceValue in source {
            current[0] = 0
            for (index, targetValue) in target.enumerated() {
                current[index + 1] = sourceValue == targetValue
                    ? previous[index] + 1
                    : max(previous[index + 1], current[index])
            }
            swap(&previous, &current)
        }
        return previous[target.count]
    }

    private static func normalize(_ token: String) -> String {
        token.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
