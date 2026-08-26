import Foundation
import Testing
@testable import ADHDCore

@Test func transcriptionCorrectionNormalizesAndFindsLearnedPhrases() throws {
    let correction = try TranscriptionCorrection(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        recognized: "  open x code  ",
        corrected: "  Open Xcode  ",
        createdAt: Date(timeIntervalSince1970: 10)
    )

    #expect(correction.recognized == "open x code")
    #expect(correction.corrected == "Open Xcode")
    #expect(correction.learnedPhrases == ["Open Xcode", "Xcode"])
    #expect(throws: VoiceLearningError.emptyRecognizedText) {
        _ = try TranscriptionCorrection(recognized: " ", corrected: "Useful")
    }
    #expect(throws: VoiceLearningError.emptyCorrectedText) {
        _ = try TranscriptionCorrection(recognized: "Useful", corrected: " ")
    }
    #expect(throws: VoiceLearningError.unchangedText) {
        _ = try TranscriptionCorrection(recognized: "same", corrected: "same")
    }
}

@Test func personalVocabularyUsesFrequencyRecencyLexicalAndAOneHundredPhraseCap() throws {
    let xcode = try TranscriptionCorrection(
        recognized: "open x code", corrected: "Open Xcode",
        createdAt: Date(timeIntervalSince1970: 1)
    )
    let xcodeAgain = try TranscriptionCorrection(
        recognized: "launch ex code", corrected: "Open Xcode",
        createdAt: Date(timeIntervalSince1970: 2)
    )
    let newer = try TranscriptionCorrection(
        recognized: "call cool van", corrected: "Call Kuvam",
        createdAt: Date(timeIntervalSince1970: 3)
    )

    let phrases = PersonalVocabulary(corrections: [newer, xcode, xcodeAgain]).phrases(limit: 4)

    #expect(phrases == ["Open Xcode", "Xcode", "Call Kuvam", "Kuvam"])

    let many = try (0..<120).map { index in
        try TranscriptionCorrection(
            recognized: "wrong \(index)", corrected: "Phrase \(index)",
            createdAt: Date(timeIntervalSince1970: Double(index))
        )
    }
    #expect(PersonalVocabulary(corrections: many).phrases(limit: 500).count == 100)
}

@Test func voiceLearningLoopPersistsEvidenceAndReturnsRankedVocabulary() async throws {
    let repository = VoiceLearningRepository()
    let loop = VoiceLearningLoop(repository: repository)

    try await loop.record(
        recognized: "call cool van", corrected: "Call Kuvam",
        at: Date(timeIntervalSince1970: 20)
    )

    let stored = try await repository.transcriptionCorrections()
    #expect(stored.count == 1)
    #expect(stored[0].corrected == "Call Kuvam")
    #expect(try await loop.vocabulary(limit: 100) == ["Call Kuvam", "Kuvam"])
}

@Test func vocabularyScopesKeepProjectTermsOutOfOtherProjects() throws {
    let global = try TranscriptionCorrection(
        recognized: "ex code",
        corrected: "Xcode",
        scope: .global
    )
    let projectA = try TranscriptionCorrection(
        recognized: "sglc",
        corrected: "SGLC",
        scope: .project,
        projectIdentifier: "release-platform"
    )
    let projectB = try TranscriptionCorrection(
        recognized: "post hog",
        corrected: "PostHog",
        scope: .project,
        projectIdentifier: "storefront"
    )
    let vocabulary = PersonalVocabulary(corrections: [global, projectA, projectB])

    #expect(vocabulary.phrases(
        scopes: [.global, .project],
        projectIdentifier: "release-platform"
    ).contains("SGLC"))
    #expect(!vocabulary.phrases(
        scopes: [.global, .project],
        projectIdentifier: "release-platform"
    ).contains("PostHog"))
}

@Test func explicitCorrectionImmediatelyCreatesMinimalTokenBoundedRule() throws {
    let first = try TranscriptionCorrection(
        recognized: "ex code",
        corrected: "Xcode",
        createdAt: Date(timeIntervalSince1970: 1),
        scope: .programming
    )
    let second = try TranscriptionCorrection(
        recognized: "ex code",
        corrected: "Xcode",
        createdAt: Date(timeIntervalSince1970: 2),
        scope: .programming
    )
    let oneOff = try TranscriptionCorrection(
        recognized: "read is",
        corrected: "Redis",
        scope: .programming
    )
    let rules = PersonalVocabulary(corrections: [first, second, oneOff])
        .normalizationRules()

    #expect(rules.count == 2)
    #expect(rules[0].recognized == "ex code")
    #expect(rules[0].evidenceCount == 2)
    #expect(DeterministicTranscriptNormalizer.apply(
        rules,
        to: "Open ex code, then explain nextcode."
    ) == "Open Xcode, then explain nextcode.")
}

@Test func correctionLearnsOnlyChangedPhraseAndHandlesHyphenatedRecognition() throws {
    let correction = try TranscriptionCorrection(
        recognized: "It was tit-for-tat in the meeting",
        corrected: "It was tip for tap in the meeting"
    )

    #expect(correction.learnedReplacement == LearnedTranscriptionReplacement(
        recognized: "tit for tat",
        corrected: "tip for tap"
    ))
    let rules = PersonalVocabulary(corrections: [correction]).normalizationRules()
    #expect(rules.count == 1)
    #expect(DeterministicTranscriptNormalizer.apply(
        rules,
        to: "They called it tit-for-tat yesterday."
    ) == "They called it tip for tap yesterday.")
}

@Test func legacyCorrectionDefaultsToPersonalScope() throws {
    let object: [String: Any] = [
        "id": "00000000-0000-0000-0000-000000000091",
        "recognized": "cool van",
        "corrected": "Kuvam",
        "createdAt": 10,
    ]
    let data = try JSONSerialization.data(withJSONObject: object)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970

    let decoded = try decoder.decode(TranscriptionCorrection.self, from: data)

    #expect(decoded.scope == .personal)
    #expect(decoded.projectIdentifier == nil)
}

private actor VoiceLearningRepository: ThoughtRepository {
    private var corrections: [TranscriptionCorrection] = []

    func save(transcriptionCorrection: TranscriptionCorrection) async throws {
        corrections.append(transcriptionCorrection)
    }

    func transcriptionCorrections() async throws -> [TranscriptionCorrection] {
        corrections
    }

    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
}
