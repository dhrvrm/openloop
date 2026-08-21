import ADHDCore
import Foundation
import Testing
@testable import LocalStore

@Test func voiceQualityEvidenceSurvivesDevelopmentStoreRestartAndFiltersByCase() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let qualityCase = try VoiceQualityCase(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000071")!,
        sourceAudioIdentifier: "sha256:release-time",
        referenceTranscript: "release time कम कर सकते हैं",
        languageSequence: ["en", "hi"],
        domainTerms: ["release time"],
        createdAt: Date(timeIntervalSince1970: 10)
    )
    let attempt = try VoiceQualityAttempt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000072")!,
        caseID: qualityCase.id,
        engineIdentifier: "qwen3-asr-0.6b",
        hypothesis: qualityCase.referenceTranscript,
        firstPartialMilliseconds: 280,
        stopToFinalMilliseconds: 720,
        createdAt: Date(timeIntervalSince1970: 20)
    )
    let writer = try JSONFileThoughtRepository(directory: directory)

    try await writer.save(voiceQualityCase: qualityCase)
    try await writer.save(voiceQualityAttempt: attempt)

    let reader = try JSONFileThoughtRepository(directory: directory)
    #expect(try await reader.voiceQualityCases() == [qualityCase])
    #expect(try await reader.voiceQualityAttempts(caseID: qualityCase.id) == [attempt])
    #expect(try await reader.voiceQualityAttempts(caseID: UUID()).isEmpty)
}

@Test func developmentStoreRejectsOrphanedVoiceQualityAttempts() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let missingCaseID = UUID()
    let attempt = try VoiceQualityAttempt(
        caseID: missingCaseID,
        engineIdentifier: "candidate",
        hypothesis: "text",
        stopToFinalMilliseconds: 100
    )
    let repository = try JSONFileThoughtRepository(directory: directory)

    await #expect(throws: VoiceQualityRepositoryError.missingCase(missingCaseID)) {
        try await repository.save(voiceQualityAttempt: attempt)
    }
}
