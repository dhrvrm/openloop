import Foundation

public enum VoiceLearningError: Error, Equatable {
    case emptyRecognizedText
    case emptyCorrectedText
    case unchangedText
}

public enum VocabularyScope: String, Codable, CaseIterable, Sendable {
    case global
    case programming
    case project
    case personal
}

public struct TranscriptionCorrection: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let recognized: String
    public let corrected: String
    public let createdAt: Date
    public let scope: VocabularyScope
    public let projectIdentifier: String?

    public init(
        id: UUID = UUID(),
        recognized: String,
        corrected: String,
        createdAt: Date = .now,
        scope: VocabularyScope = .personal,
        projectIdentifier: String? = nil
    ) throws {
        let recognized = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recognized.isEmpty else { throw VoiceLearningError.emptyRecognizedText }
        guard !corrected.isEmpty else { throw VoiceLearningError.emptyCorrectedText }
        guard recognized != corrected else { throw VoiceLearningError.unchangedText }
        self.id = id
        self.recognized = recognized
        self.corrected = corrected
        self.createdAt = createdAt
        self.scope = scope
        self.projectIdentifier = projectIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var learnedPhrases: [String] {
        let correctedTokens = Self.tokens(in: corrected)
        let recognizedSet = Set(Self.tokens(in: recognized).map(Self.key(for:)))
        var phrases: [String] = correctedTokens.count > 1 ? [corrected] : []
        phrases.append(contentsOf: correctedTokens.filter {
            !recognizedSet.contains(Self.key(for: $0))
        })
        if phrases.isEmpty { phrases = [corrected] }
        return Self.unique(phrases)
    }

    private static func tokens(in text: String) -> [String] {
        var result: [String] = []
        var token = ""
        for character in text {
            if character.isLetter || character.isNumber {
                token.append(character)
            } else if !token.isEmpty {
                result.append(token)
                token = ""
            }
        }
        if !token.isEmpty { result.append(token) }
        return result
    }

    fileprivate static func key(for phrase: String) -> String {
        phrase.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func unique(_ phrases: [String]) -> [String] {
        var seen: Set<String> = []
        return phrases.filter { seen.insert(key(for: $0)).inserted }
    }


    private enum CodingKeys: String, CodingKey {
        case id, recognized, corrected, createdAt, scope, projectIdentifier
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            recognized: values.decode(String.self, forKey: .recognized),
            corrected: values.decode(String.self, forKey: .corrected),
            createdAt: values.decode(Date.self, forKey: .createdAt),
            scope: values.decodeIfPresent(VocabularyScope.self, forKey: .scope) ?? .personal,
            projectIdentifier: values.decodeIfPresent(String.self, forKey: .projectIdentifier)
        )
    }
}

public struct TranscriptionNormalizationRule: Equatable, Sendable {
    public let recognized: String
    public let corrected: String
    public let scope: VocabularyScope
    public let projectIdentifier: String?
    public let evidenceCount: Int

    public init(
        recognized: String,
        corrected: String,
        scope: VocabularyScope,
        projectIdentifier: String?,
        evidenceCount: Int
    ) {
        self.recognized = recognized
        self.corrected = corrected
        self.scope = scope
        self.projectIdentifier = projectIdentifier
        self.evidenceCount = evidenceCount
    }
}

public struct PersonalVocabulary: Sendable {
    private let corrections: [TranscriptionCorrection]

    public init(corrections: [TranscriptionCorrection]) {
        self.corrections = corrections
    }

    public func phrases(
        limit requestedLimit: Int = 100,
        scopes: Set<VocabularyScope> = Set(VocabularyScope.allCases),
        projectIdentifier: String? = nil
    ) -> [String] {
        struct Evidence {
            var phrase: String
            var count: Int
            var latest: Date
        }

        var evidence: [String: Evidence] = [:]
        for correction in filteredCorrections(
            scopes: scopes,
            projectIdentifier: projectIdentifier
        ) {
            for phrase in correction.learnedPhrases {
                let key = TranscriptionCorrection.key(for: phrase)
                if var existing = evidence[key] {
                    existing.count += 1
                    if correction.createdAt >= existing.latest {
                        existing.latest = correction.createdAt
                        existing.phrase = phrase
                    }
                    evidence[key] = existing
                } else {
                    evidence[key] = Evidence(
                        phrase: phrase, count: 1, latest: correction.createdAt
                    )
                }
            }
        }

        let limit = max(0, min(requestedLimit, 100))
        return evidence.values.sorted { left, right in
            if left.count != right.count { return left.count > right.count }
            if left.latest != right.latest { return left.latest > right.latest }
            return left.phrase.compare(
                right.phrase,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: nil,
                locale: Locale(identifier: "en_US_POSIX")
            ) == .orderedAscending
        }.prefix(limit).map(\.phrase)
    }

    public func normalizationRules(
        minimumEvidence: Int = 2,
        maximumRecognizedTokens: Int = 5,
        scopes: Set<VocabularyScope> = Set(VocabularyScope.allCases),
        projectIdentifier: String? = nil
    ) -> [TranscriptionNormalizationRule] {
        struct RuleKey: Hashable {
            let recognized: String
            let corrected: String
            let scope: VocabularyScope
            let projectIdentifier: String?
        }
        var counts: [RuleKey: Int] = [:]
        for correction in filteredCorrections(
            scopes: scopes,
            projectIdentifier: projectIdentifier
        ) where Self.tokenCount(correction.recognized) <= max(1, maximumRecognizedTokens) {
            let key = RuleKey(
                recognized: TranscriptionCorrection.key(for: correction.recognized),
                corrected: correction.corrected,
                scope: correction.scope,
                projectIdentifier: correction.projectIdentifier
            )
            counts[key, default: 0] += 1
        }
        return counts.compactMap { key, count in
            guard count >= max(2, minimumEvidence) else { return nil }
            return TranscriptionNormalizationRule(
                recognized: key.recognized,
                corrected: key.corrected,
                scope: key.scope,
                projectIdentifier: key.projectIdentifier,
                evidenceCount: count
            )
        }.sorted {
            if $0.evidenceCount != $1.evidenceCount { return $0.evidenceCount > $1.evidenceCount }
            return $0.recognized < $1.recognized
        }
    }

    private func filteredCorrections(
        scopes: Set<VocabularyScope>,
        projectIdentifier: String?
    ) -> [TranscriptionCorrection] {
        corrections.filter { correction in
            guard scopes.contains(correction.scope) else { return false }
            guard correction.scope == .project else { return true }
            return correction.projectIdentifier == projectIdentifier
        }
    }

    private static func tokenCount(_ value: String) -> Int {
        value.split { !$0.isLetter && !$0.isNumber }.count
    }
}

public enum DeterministicTranscriptNormalizer {
    public static func apply(
        _ rules: [TranscriptionNormalizationRule],
        to text: String
    ) -> String {
        rules.reduce(text) { result, rule in
            replaceTokenAnchored(rule.recognized, with: rule.corrected, in: result)
        }
    }

    private static func replaceTokenAnchored(
        _ recognized: String,
        with corrected: String,
        in text: String
    ) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: recognized)
            .replacingOccurrences(of: "\\ ", with: "\\s+")
        guard let expression = try? NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])",
            options: [.caseInsensitive]
        ) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: corrected)
        )
    }
}

public struct VoiceLearningLoop: Sendable {
    private let repository: any ThoughtRepository

    public init(repository: any ThoughtRepository) {
        self.repository = repository
    }

    public func record(
        recognized: String,
        corrected: String,
        at: Date = .now,
        scope: VocabularyScope = .personal,
        projectIdentifier: String? = nil
    ) async throws {
        let correction = try TranscriptionCorrection(
            recognized: recognized,
            corrected: corrected,
            createdAt: at,
            scope: scope,
            projectIdentifier: projectIdentifier
        )
        try await repository.save(transcriptionCorrection: correction)
    }

    public func vocabulary(limit: Int = 100) async throws -> [String] {
        let corrections = try await repository.transcriptionCorrections()
        return PersonalVocabulary(corrections: corrections).phrases(limit: limit)
    }


    public func normalizationRules(
        minimumEvidence: Int = 2,
        projectIdentifier: String? = nil
    ) async throws -> [TranscriptionNormalizationRule] {
        PersonalVocabulary(corrections: try await repository.transcriptionCorrections())
            .normalizationRules(
                minimumEvidence: minimumEvidence,
                projectIdentifier: projectIdentifier
            )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
