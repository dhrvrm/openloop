import Foundation

public enum MeetingInsightKind: String, Codable, Equatable, Sendable {
    case summary
    case decision
    case actionCandidate
}

public struct MeetingEvidence: Codable, Equatable, Sendable {
    public let segmentID: UUID
    public let start: TimeInterval
    public let speaker: String?
    public let excerpt: String

    public init(
        segmentID: UUID,
        start: TimeInterval,
        speaker: String?,
        excerpt: String
    ) {
        self.segmentID = segmentID
        self.start = start
        self.speaker = speaker
        self.excerpt = excerpt
    }
}

public struct MeetingInsight: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: MeetingInsightKind
    public let text: String
    public let evidence: MeetingEvidence

    public init(
        id: String,
        kind: MeetingInsightKind,
        text: String,
        evidence: MeetingEvidence
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.evidence = evidence
    }
}

public struct MeetingIntelligence: Codable, Equatable, Sendable {
    public let summary: [MeetingInsight]
    public let decisions: [MeetingInsight]
    public let actionCandidates: [MeetingInsight]

    public init(
        summary: [MeetingInsight],
        decisions: [MeetingInsight],
        actionCandidates: [MeetingInsight]
    ) {
        self.summary = summary
        self.decisions = decisions
        self.actionCandidates = actionCandidates
    }
}

/// Produces a private, deterministic meeting brief from exact transcript sentences.
/// It deliberately extracts instead of rewriting so every visible claim remains auditable.
public struct MeetingIntelligenceCompiler: Sendable {
    public init() {}

    public func compile(_ transcript: MeetingTranscript) -> MeetingIntelligence {
        let sentences = transcript.segments.flatMap(Self.sentences)
        guard !sentences.isEmpty else {
            return MeetingIntelligence(summary: [], decisions: [], actionCandidates: [])
        }

        let decisions = sentences.compactMap { sentence in
            Self.isExplicitDecision(sentence.text)
                ? Self.insight(.decision, from: sentence)
                : nil
        }
        let actions = sentences.compactMap { sentence in
            Self.isExplicitAction(sentence.text)
                ? Self.insight(.actionCandidate, from: sentence)
                : nil
        }

        return MeetingIntelligence(
            summary: Self.summary(from: sentences),
            decisions: Self.deduplicated(decisions),
            actionCandidates: Self.deduplicated(actions)
        )
    }
}

private extension MeetingIntelligenceCompiler {
    struct Sentence {
        let segment: TranscriptSegment
        let index: Int
        let transcriptOrder: Int
        let text: String
        let terms: Set<String>
    }

    static let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from",
        "has", "have", "i", "in", "is", "it", "of", "on", "or", "our", "so",
        "that", "the", "their", "this", "to", "was", "we", "were", "with", "you",
        "और", "का", "की", "के", "को", "है", "हैं", "था", "थी", "थे", "में",
        "पर", "से", "यह", "ये", "वो", "हम", "मैं", "तो", "भी", "कर", "करके",
        "ab", "aur", "hai", "hain", "hum", "main", "mein", "par", "se", "to", "ye",
    ]

    static func sentences(in segment: TranscriptSegment) -> [Sentence] {
        var pieces: [String] = []
        var buffer = ""
        func flush() {
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { pieces.append(text) }
            buffer = ""
        }

        for character in segment.text {
            buffer.append(character)
            if character == "." || character == "!" || character == "?"
                || character == "।" || character == "\n" {
                flush()
            }
        }
        flush()

        return pieces.enumerated().map { index, text in
            Sentence(
                segment: segment,
                index: index,
                transcriptOrder: 0,
                text: text,
                terms: meaningfulTerms(in: text)
            )
        }
    }

    static func summary(from input: [Sentence]) -> [MeetingInsight] {
        let sentences = input.enumerated().map { order, value in
            Sentence(
                segment: value.segment,
                index: value.index,
                transcriptOrder: order,
                text: value.text,
                terms: value.terms
            )
        }
        let frequencies = sentences.reduce(into: [String: Int]()) { counts, sentence in
            for term in sentence.terms { counts[term, default: 0] += 1 }
        }
        let ranked = sentences.sorted { lhs, rhs in
            let left = summaryScore(lhs, frequencies: frequencies, count: sentences.count)
            let right = summaryScore(rhs, frequencies: frequencies, count: sentences.count)
            if left == right { return lhs.transcriptOrder < rhs.transcriptOrder }
            return left > right
        }

        var selected: [Sentence] = []
        var normalized = Set<String>()
        for sentence in ranked {
            let key = normalizedText(sentence.text)
            guard !key.isEmpty, normalized.insert(key).inserted else { continue }
            guard selected.allSatisfy({ jaccard(sentence.terms, $0.terms) < 0.8 }) else { continue }
            selected.append(sentence)
            if selected.count == 3 { break }
        }

        return selected
            .sorted { $0.transcriptOrder < $1.transcriptOrder }
            .map { insight(.summary, from: $0) }
    }

    static func summaryScore(
        _ sentence: Sentence,
        frequencies: [String: Int],
        count: Int
    ) -> Double {
        let centrality = sentence.terms.sorted().reduce(0.0) {
            $0 + log1p(Double(frequencies[$1, default: 0]))
        } / sqrt(Double(max(1, sentence.terms.count)))
        let position = 0.25 * (1 - Double(sentence.transcriptOrder) / Double(max(1, count)))
        let explicit = isExplicitDecision(sentence.text) || isExplicitAction(sentence.text) ? 0.5 : 0
        let thinPenalty = sentence.terms.count < 3 ? 0.75 : 0
        return centrality + position + explicit - thinPenalty
    }

    static func insight(_ kind: MeetingInsightKind, from sentence: Sentence) -> MeetingInsight {
        MeetingInsight(
            id: "\(kind.rawValue):\(sentence.segment.id.uuidString):\(sentence.index)",
            kind: kind,
            text: sentence.text,
            evidence: MeetingEvidence(
                segmentID: sentence.segment.id,
                start: sentence.segment.start,
                speaker: sentence.segment.speaker,
                excerpt: sentence.text
            )
        )
    }

    static func isExplicitDecision(_ text: String) -> Bool {
        let value = searchable(text)
        guard !isQuestion(value) else { return false }
        let speculation: Set<String> = ["maybe", "perhaps", "might", "could", "may", "शायद"]
        guard speculation.isDisjoint(with: tokens(in: value)) else { return false }
        let markers = [
            "decision:", "we decided", "it was decided", "we agreed", "agreed to",
            "finalized", "finalised", "तय किया", "तय हुआ", "फैसला", "निर्णय",
            "सहमति", " final है", "final hai",
        ]
        return markers.contains { value.contains($0) }
    }

    static func isExplicitAction(_ text: String) -> Bool {
        let value = " \(searchable(text)) "
        guard !isQuestion(value) else { return false }
        let uncertainty: Set<String> = ["maybe", "perhaps", "might", "could", "may", "शायद"]
        guard uncertainty.isDisjoint(with: tokens(in: value)) else { return false }
        let exclusions = [
            " should ", " will not ", " won't ", " cannot ", " can't ", " नहीं ", " मत ",
        ]
        guard exclusions.allSatisfy({ !value.contains($0) }) else { return false }

        let anchored = [" action item:", " todo:", " follow up:", " follow-up:"]
        if anchored.contains(where: { value.contains($0) }) { return true }

        let commitments = [
            " i will ", " i'll ", " i’ll ", " we will ", " we'll ", " we’ll ",
            " करना है ", " भेजना है ", " बनाना है ", " देखना है ", " बताना है ",
            " karna hai ", " bhejna hai ", " banana hai ",
        ]
        if commitments.contains(where: { value.contains($0) }) { return true }
        if hasExplicitNamedWillCommitment(text) { return true }

        let futureSuffixes = [
            "करूंगा", "करूँगा", "करूंगी", "करूँगी", "करेंगे", "करेगा", "करेगी",
            "भेजूंगा", "भेजूँगा", "भेजूंगी", "भेजूँगी", "भेजेंगे", "भेजेगा", "भेजेगी",
            "बनाऊंगा", "बनाऊँगा", "बनाऊंगी", "बनाऊँगी", "बनाएंगे", "बनाएगा", "बनाएगी",
            "karunga", "karungi", "karenge", "karega", "karegi", "bhejega", "bhejegi",
        ]
        return tokens(in: value).contains { token in futureSuffixes.contains(token) }
    }

    static func hasExplicitNamedWillCommitment(_ text: String) -> Bool {
        let pattern = #"^\s*([\p{Lu}][\p{L}'’.-]*(?:\s+[\p{L}'’.-]+){0,3})\s+will\s+(send|share|prepare|review|finish|update|create|call|deliver|complete|fix|write|publish|upload|check|schedule|email|meet|bring|submit|own|handle)\b"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return false }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: fullRange),
              let subjectRange = Range(match.range(at: 1), in: text)
        else { return false }
        let subject = String(text[subjectRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard subject.first?.isUppercase == true else { return false }
        let subjectTokens = tokens(in: subject)
        let nonhuman = Set([
            "app", "application", "automation", "build", "code", "integration", "model",
            "pipeline", "process", "script", "service", "system", "telemetry", "rain",
            "demand", "nothing", "this", "that", "it",
        ])
        guard subjectTokens.allSatisfy({ !nonhuman.contains($0) }) else { return false }
        if subjectTokens.first == "the" || subjectTokens.first == "a" || subjectTokens.first == "an" {
            return subjectTokens.last == "team"
        }
        return true
    }

    static func isQuestion(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") { return true }
        let questionStarts: Set<String> = [
            "क्या", "कब", "कौन", "कैसे", "क्यों", "where", "when", "who", "how", "why",
            "have", "has", "did", "do", "does", "can", "could", "would", "should", "will",
            "is", "are", "was", "were", "am",
        ]
        return tokens(in: trimmed).first.map(questionStarts.contains) ?? false
    }

    static func meaningfulTerms(in text: String) -> Set<String> {
        Set(tokens(in: text).filter { $0.count > 1 && !stopwords.contains($0) })
    }

    static func tokens(in text: String) -> [String] {
        let value = searchable(text)
        var output: [String] = []
        var token = ""
        for scalar in value.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                token.unicodeScalars.append(scalar)
            } else if !token.isEmpty {
                output.append(token)
                token = ""
            }
        }
        if !token.isEmpty { output.append(token) }
        return output
    }

    static func searchable(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
    }

    static func normalizedText(_ text: String) -> String {
        tokens(in: text).joined(separator: " ")
    }

    static func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty || !rhs.isEmpty else { return 1 }
        return Double(lhs.intersection(rhs).count) / Double(lhs.union(rhs).count)
    }

    static func deduplicated(_ insights: [MeetingInsight]) -> [MeetingInsight] {
        var seen = Set<String>()
        return insights.filter { seen.insert(normalizedText($0.text)).inserted }
    }
}
