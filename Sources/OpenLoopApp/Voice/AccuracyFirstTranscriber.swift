import ADHDCore
import Foundation

/// Cross-checks local recognizers and preserves disagreements as reviewable evidence.
actor AccuracyFirstTranscriber: MeetingTranscribing {
    nonisolated let modelIdentifier: String

    private let primary: any MeetingTranscribing
    private let witness: any MeetingTranscribing
    private let expectedDomainTerms: @Sendable () async -> [String]
    private let policy: TranscriptFusionPolicy
    private let crossCheckAllPrimarySpans: Bool

    init(
        primary: any MeetingTranscribing,
        witness: any MeetingTranscribing,
        expectedDomainTerms: @escaping @Sendable () async -> [String] = { [] },
        policy: TranscriptFusionPolicy = TranscriptFusionPolicy(),
        crossCheckAllPrimarySpans: Bool = true
    ) {
        self.primary = primary
        self.witness = witness
        self.expectedDomainTerms = expectedDomainTerms
        self.policy = policy
        self.crossCheckAllPrimarySpans = crossCheckAllPrimarySpans
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
        let requiresWitness = crossCheckAllPrimarySpans || primaryEvidence.contains {
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
        let witnessEvidence = Self.witnessEvidence(
            output: witnessOutput,
            engineIdentifier: witness.modelIdentifier,
            alignedTo: primaryEvidence
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

    private static func witnessEvidence(
        output: LocalTranscriptionOutput,
        engineIdentifier: String,
        alignedTo primary: [TranscriptEvidence]
    ) -> [TranscriptEvidence] {
        let evidence = evidence(output: output, engineIdentifier: engineIdentifier)
        guard primary.count == 1, evidence.count > 1,
              let start = evidence.map(\.start).min(),
              let end = evidence.map(\.end).max()
        else { return evidence }
        let text = evidence.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
        guard !text.isEmpty else { return evidence }
        return [TranscriptEvidence(
            engineIdentifier: engineIdentifier,
            text: text,
            start: start,
            end: end,
            detectedLanguage: output.detectedLanguage
        )]
    }

    private static func output(
        _ primary: LocalTranscriptionOutput,
        fusion: TranscriptFusionResult,
        modelIdentifier: String
    ) -> LocalTranscriptionOutput {
        let selected = Dictionary(uniqueKeysWithValues: fusion.spans.map {
            ($0.primary.id, $0.selectedText)
        })
        let segments = primary.segments.map { segment in
            guard let text = selected[segment.id], text != segment.text,
                  let replacement = try? TranscriptSegment(
                    id: segment.id,
                    start: segment.start,
                    end: segment.end,
                    text: text,
                    speaker: segment.speaker,
                    speakerProfileID: segment.speakerProfileID
                  ) else { return segment }
            return replacement
        }
        return LocalTranscriptionOutput(
            duration: primary.duration,
            detectedLanguage: primary.detectedLanguage,
            modelIdentifier: modelIdentifier,
            segments: segments,
            fusionEvidence: fusion,
            speakerSeparation: primary.speakerSeparation,
            speakerFingerprints: primary.speakerFingerprints
        )
    }
}
