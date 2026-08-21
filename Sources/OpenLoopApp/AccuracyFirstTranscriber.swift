import ADHDCore
import Foundation

/// Runs the second recognizer only when the primary evidence indicates risk.
/// The returned transcript remains primary text; disagreements are attached as
/// reviewable evidence instead of being silently rewritten.
actor AccuracyFirstTranscriber: MeetingTranscribing {
    nonisolated let modelIdentifier: String

    private let primary: any MeetingTranscribing
    private let witness: any MeetingTranscribing
    private let expectedDomainTerms: @Sendable () async -> [String]
    private let policy: TranscriptFusionPolicy

    init(
        primary: any MeetingTranscribing,
        witness: any MeetingTranscribing,
        expectedDomainTerms: @escaping @Sendable () async -> [String] = { [] },
        policy: TranscriptFusionPolicy = TranscriptFusionPolicy()
    ) {
        self.primary = primary
        self.witness = witness
        self.expectedDomainTerms = expectedDomainTerms
        self.policy = policy
        modelIdentifier = "Accuracy-first · \(primary.modelIdentifier) + selective \(witness.modelIdentifier)"
    }

    func diagnostics() async -> MeetingEngineDiagnostics {
        await primary.diagnostics()
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
        let primaryOutput: LocalTranscriptionOutput
        do {
            primaryOutput = try await primary.transcribe(
                audioURL: audioURL,
                languageCode: languageCode,
                progress: progress
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await progress(.init(
                stage: .transcribing,
                fraction: 0.1,
                message: "Primary recognizer failed; using the local witness"
            ))
            return try await witness.transcribe(
                audioURL: audioURL,
                languageCode: languageCode,
                progress: progress
            )
        }

        let terms = await expectedDomainTerms()
        let primaryEvidence = Self.evidence(
            output: primaryOutput,
            engineIdentifier: primary.modelIdentifier
        )
        let requiresWitness = primaryEvidence.contains {
            !policy.reasonsToRequestSecondary(for: $0, expectedDomainTerms: terms).isEmpty
        }
        guard requiresWitness else {
            let fusion = policy.fuse(
                primary: primaryEvidence,
                secondary: [],
                expectedDomainTerms: terms
            )
            return Self.output(primaryOutput, fusion: fusion, modelIdentifier: modelIdentifier)
        }

        await progress(.init(
            stage: .transcribing,
            fraction: 0.85,
            message: "Cross-checking uncertain multilingual spans locally",
            previewText: primaryOutput.segments.map(\.text).joined(separator: "\n")
        ))
        let witnessOutput: LocalTranscriptionOutput
        do {
            witnessOutput = try await witness.transcribe(
                audioURL: audioURL,
                languageCode: languageCode,
                progress: { _ in }
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let fusion = policy.fuse(
                primary: primaryEvidence,
                secondary: [],
                expectedDomainTerms: terms
            )
            return Self.output(primaryOutput, fusion: fusion, modelIdentifier: modelIdentifier)
        }
        let witnessEvidence = Self.evidence(
            output: witnessOutput,
            engineIdentifier: witness.modelIdentifier
        )
        let fusion = policy.fuse(
            primary: primaryEvidence,
            secondary: witnessEvidence,
            expectedDomainTerms: terms
        )
        return Self.output(primaryOutput, fusion: fusion, modelIdentifier: modelIdentifier)
    }

    private static func evidence(
        output: LocalTranscriptionOutput,
        engineIdentifier: String
    ) -> [TranscriptEvidence] {
        output.segments.map {
            TranscriptEvidence(
                id: $0.id,
                engineIdentifier: engineIdentifier,
                text: $0.text,
                start: $0.start,
                end: $0.end,
                detectedLanguage: output.detectedLanguage
            )
        }
    }

    private static func output(
        _ primary: LocalTranscriptionOutput,
        fusion: TranscriptFusionResult,
        modelIdentifier: String
    ) -> LocalTranscriptionOutput {
        LocalTranscriptionOutput(
            duration: primary.duration,
            detectedLanguage: primary.detectedLanguage,
            modelIdentifier: modelIdentifier,
            segments: primary.segments,
            fusionEvidence: fusion
        )
    }
}
