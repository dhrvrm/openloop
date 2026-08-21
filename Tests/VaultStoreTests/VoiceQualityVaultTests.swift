import ADHDCore
import Foundation
import Testing
@testable import VaultStore

@Test func voiceQualityEvidenceSurvivesEncryptedVaultRestartWithoutPlaintextLeak() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let key = Data(repeating: 0x33, count: 32)
    let secretReference = "हम release time कम कर सकते हैं for SGLC releases"
    let qualityCase = try VoiceQualityCase(
        sourceAudioIdentifier: "sha256:private-hinglish",
        referenceTranscript: secretReference,
        languageSequence: ["hi", "en", "hi", "en"],
        domainTerms: ["SGLC"]
    )
    let attempt = try VoiceQualityAttempt(
        caseID: qualityCase.id,
        engineIdentifier: "qwen3-asr-0.6b",
        hypothesis: secretReference,
        firstPartialMilliseconds: 260,
        stopToFinalMilliseconds: 640
    )
    let writer = try EncryptedThoughtRepository(directory: directory, keyData: key)

    try await writer.save(voiceQualityCase: qualityCase)
    try await writer.save(voiceQualityAttempt: attempt)

    let vaultURL = await writer.fileURL
    let rawVault = try Data(contentsOf: vaultURL)
    #expect(rawVault.range(of: Data(secretReference.utf8)) == nil)
    let reader = try EncryptedThoughtRepository(directory: directory, keyData: key)
    #expect(try await reader.voiceQualityCases() == [qualityCase])
    #expect(try await reader.voiceQualityAttempts(caseID: qualityCase.id) == [attempt])
}

@Test func encryptedVaultResetClearsVoiceQualityEvidence() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try EncryptedThoughtRepository(
        directory: directory,
        keyData: Data(repeating: 0x34, count: 32)
    )
    let qualityCase = try VoiceQualityCase(
        sourceAudioIdentifier: "sha256:reset",
        referenceTranscript: "निजी transcript",
        languageSequence: ["hi", "en"]
    )
    try await repository.save(voiceQualityCase: qualityCase)

    try await repository.resetAllData()

    #expect(try await repository.voiceQualityCases().isEmpty)
    #expect(try await repository.voiceQualityAttempts(caseID: nil).isEmpty)
    #expect(try await repository.empty())
}
