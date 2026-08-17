import Foundation

public enum VoiceLearningError: Error, Equatable {
    case emptyRecognizedText
    case emptyCorrectedText
    case unchangedText
}

public struct TranscriptionCorrection: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let recognized: String
    public let corrected: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        recognized: String,
        corrected: String,
        createdAt: Date = .now
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
}

public struct PersonalVocabulary: Sendable {
    private let corrections: [TranscriptionCorrection]

    public init(corrections: [TranscriptionCorrection]) {
        self.corrections = corrections
    }

    public func phrases(limit requestedLimit: Int = 100) -> [String] {
        struct Evidence {
            var phrase: String
            var count: Int
            var latest: Date
        }

        var evidence: [String: Evidence] = [:]
        for correction in corrections {
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
}

public struct VoiceLearningLoop: Sendable {
    private let repository: any ThoughtRepository

    public init(repository: any ThoughtRepository) {
        self.repository = repository
    }

    public func record(recognized: String, corrected: String, at: Date = .now) async throws {
        let correction = try TranscriptionCorrection(
            recognized: recognized, corrected: corrected, createdAt: at
        )
        try await repository.save(transcriptionCorrection: correction)
    }

    public func vocabulary(limit: Int = 100) async throws -> [String] {
        let corrections = try await repository.transcriptionCorrections()
        return PersonalVocabulary(corrections: corrections).phrases(limit: limit)
    }
}
