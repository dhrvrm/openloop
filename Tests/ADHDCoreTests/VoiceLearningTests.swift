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
