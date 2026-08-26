import ADHDCore
import Foundation

/// Applies corrections the user explicitly taught after recognition and fusion,
/// while preserving timing, speaker identity, and model evidence.
actor TranscriptNormalizingTranscriber: MeetingTranscribing {
    nonisolated let modelIdentifier: String

    private let base: any MeetingTranscribing
    private let rules: @Sendable () async -> [TranscriptionNormalizationRule]

    init(
        base: any MeetingTranscribing,
        rules: @escaping @Sendable () async -> [TranscriptionNormalizationRule]
    ) {
        self.base = base
        self.rules = rules
        modelIdentifier = base.modelIdentifier
    }

    func diagnostics() async -> MeetingEngineDiagnostics {
        await base.diagnostics()
    }

    func transcribe(
        audioURL: URL,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput {
        try await transcribe(audioURL: audioURL, languageCode: nil, progress: progress)
    }

    func transcribe(
        audioURL: URL,
        languageCode: String?,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput {
        let output = try await base.transcribe(
            audioURL: audioURL,
            languageCode: languageCode,
            progress: progress
        )
        let learnedRules = await rules()
        guard !learnedRules.isEmpty else { return output }
        let normalizedSegments = try output.segments.map { segment in
            try TranscriptSegment(
                id: segment.id,
                start: segment.start,
                end: segment.end,
                text: DeterministicTranscriptNormalizer.apply(learnedRules, to: segment.text),
                speaker: segment.speaker,
                speakerProfileID: segment.speakerProfileID
            )
        }
        return LocalTranscriptionOutput(
            duration: output.duration,
            detectedLanguage: output.detectedLanguage,
            modelIdentifier: output.modelIdentifier,
            segments: normalizedSegments,
            fusionEvidence: output.fusionEvidence,
            speakerSeparation: output.speakerSeparation,
            speakerFingerprints: output.speakerFingerprints
        )
    }
}
