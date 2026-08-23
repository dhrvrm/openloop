import ADHDCore
import Testing
import WhisperKit
@testable import OpenLoopApp

@Test func whisperProgressEstimateIsBoundedForLongMeetings() {
    #expect(WhisperKitMeetingTranscriber.estimatedFraction(
        windowID: 0,
        inputAudioSeconds: 30,
        duration: 1_500
    ) == 0.02)
    #expect(WhisperKitMeetingTranscriber.estimatedFraction(
        windowID: 90,
        inputAudioSeconds: 2_000,
        duration: 1_500
    ) == 0.98)
    let fallback = WhisperKitMeetingTranscriber.estimatedFraction(
        windowID: 2,
        inputAudioSeconds: 0,
        duration: 0
    )
    #expect(abs(fallback - 0.15) < 0.000_001)
}

@Test func languageSummaryPreservesFirstSeenLanguages() {
    #expect(WhisperKitMeetingTranscriber.languageSummary(["en", "en", "hi", "hi"]) == "en + hi")
    #expect(WhisperKitMeetingTranscriber.languageSummary(["hi"]) == "hi")
    #expect(WhisperKitMeetingTranscriber.languageSummary(["", "  "]) == nil)
}

@Test func spokenLanguageSummaryRecognizesEnglishHindiScriptsInOrder() throws {
    let englishFirst = [
        try TranscriptSegment(
            start: 0,
            end: 3,
            text: "Hello this is Dhruv. अब मैं हिंदी में बात कर रहा हूँ।"
        ),
    ]
    let hindiOnly = [
        try TranscriptSegment(start: 0, end: 2, text: "अब मैं हिंदी में बात कर रहा हूँ।"),
    ]
    let spanish = [
        try TranscriptSegment(start: 0, end: 2, text: "Hola, estamos listos."),
    ]

    #expect(WhisperKitMeetingTranscriber.spokenLanguageSummary(
        modelLanguage: "hi",
        segments: englishFirst
    ) == "en + hi")
    #expect(WhisperKitMeetingTranscriber.spokenLanguageSummary(
        modelLanguage: "hi",
        segments: hindiOnly
    ) == "hi")
    #expect(WhisperKitMeetingTranscriber.spokenLanguageSummary(
        modelLanguage: "es",
        segments: spanish
    ) == "es")
    #expect(WhisperKitMeetingTranscriber.spokenLanguageSummary(
        modelLanguage: "en + hi",
        segments: englishFirst
    ) == "en + hi")
}

@Test func languageProbeMarginAndCoreOwnershipAreDeterministic() {
    #expect(WhisperKitMeetingTranscriber.languageConfidenceMargin([
        "en": -0.1,
        "hi": -0.8,
        "fr": -2,
    ]) == 0.7)

    let segment = TranscriptionSegment(
        start: 0.8,
        end: 1.8,
        text: " hello नमस्ते",
        words: [
            WordTiming(word: " hello", tokens: [], start: 0.8, end: 1.1, probability: 0.9),
            WordTiming(word: " नमस्ते", tokens: [], start: 1.2, end: 1.8, probability: 0.9),
        ]
    )

    let retained = WhisperKitMeetingTranscriber.trim(
        [segment],
        to: (16_000 * 1)..<(16_000 * 2)
    )
    #expect(retained.count == 1)
    #expect(retained.first?.text == " नमस्ते")
    #expect(retained.first?.words?.count == 1)

    let boundary = TranscriptionSegment(
        start: 0.7,
        end: 1.3,
        text: " tail अब",
        words: [
            WordTiming(word: " tail", tokens: [], start: 0.7, end: 0.85, probability: 0.9),
            WordTiming(word: " अब", tokens: [], start: 0.86, end: 0.98, probability: 0.9),
            WordTiming(word: " हिंदी", tokens: [], start: 1.01, end: 1.3, probability: 0.9),
        ]
    )
    let hindiBoundary = WhisperKitMeetingTranscriber.trim(
        [boundary],
        to: (16_000 * 1)..<(16_000 * 2),
        leadingContextLanguage: "hi"
    )
    #expect(hindiBoundary.first?.text == " अब हिंदी")

    let outgoing = WhisperKitMeetingTranscriber.trim(
        [boundary],
        to: 0..<(16_000 * 1),
        leadingContextLanguage: "en"
    )
    let outgoingResult = TranscriptionResult(
        text: outgoing.map(\.text).joined(),
        segments: outgoing,
        language: "en",
        timings: TranscriptionTimings()
    )
    let incomingResult = TranscriptionResult(
        text: hindiBoundary.map(\.text).joined(),
        segments: hindiBoundary,
        language: "hi",
        timings: TranscriptionTimings()
    )
    let chunks = [
        PlannedAudioChunk(coreRange: 0..<(16_000 * 1), decodeRange: 0..<(16_000 * 2)),
        PlannedAudioChunk(coreRange: (16_000 * 1)..<(16_000 * 2), decodeRange: 0..<(16_000 * 2)),
    ]
    let reconciled = WhisperKitMeetingTranscriber.deduplicateBoundaryWords(
        [[outgoingResult], [incomingResult]],
        chunks: chunks
    )
    let combinedWords = reconciled
        .flatMap { $0 }
        .flatMap(\.segments)
        .compactMap(\.words)
        .flatMap { $0 }
        .map { $0.word.trimmingCharacters(in: .whitespacesAndNewlines) }
    #expect(combinedWords.filter { $0 == "अब" }.count == 1)

    let repeatedCore = TranscriptionSegment(
        start: 1.02,
        end: 1.2,
        text: " yes",
        words: [WordTiming(
            word: " yes",
            tokens: [],
            start: 1.02,
            end: 1.2,
            probability: 0.9
        )]
    )
    let repeatedResult = TranscriptionResult(
        text: " yes",
        segments: [repeatedCore],
        language: "en",
        timings: TranscriptionTimings()
    )
    let priorRepeatedResult = TranscriptionResult(
        text: " yes",
        segments: [TranscriptionSegment(
            start: 0.85,
            end: 0.98,
            text: " yes",
            words: [WordTiming(
                word: " yes",
                tokens: [],
                start: 0.85,
                end: 0.98,
                probability: 0.9
            )]
        )],
        language: "en",
        timings: TranscriptionTimings()
    )
    let repeated = WhisperKitMeetingTranscriber.deduplicateBoundaryWords(
        [[priorRepeatedResult], [repeatedResult]],
        chunks: chunks
    )
    let repeatedWords = repeated.flatMap { $0 }.flatMap(\.segments)
        .compactMap(\.words).flatMap { $0 }.map { $0.word.trimmingCharacters(in: .whitespaces) }
    #expect(repeatedWords.filter { $0 == "yes" }.count == 2)

    let recoveredRepeat = TranscriptionResult(
        text: " yes",
        segments: [TranscriptionSegment(
            start: 0.86,
            end: 1.02,
            text: " yes",
            words: [WordTiming(
                word: " yes",
                tokens: [],
                start: 0.86,
                end: 1.02,
                probability: 0.9
            )]
        )],
        language: "en",
        timings: TranscriptionTimings()
    )
    let earlierOnly = TranscriptionResult(
        text: " yes",
        segments: [TranscriptionSegment(
            start: 0.0,
            end: 0.2,
            text: " yes",
            words: [WordTiming(
                word: " yes",
                tokens: [],
                start: 0.0,
                end: 0.2,
                probability: 0.9
            )]
        )],
        language: "en",
        timings: TranscriptionTimings()
    )
    let recovered = WhisperKitMeetingTranscriber.deduplicateBoundaryWords(
        [[earlierOnly], [recoveredRepeat]],
        chunks: chunks
    )
    let recoveredWords = recovered.flatMap { $0 }.flatMap(\.segments)
        .compactMap(\.words).flatMap { $0 }
    #expect(recoveredWords.count == 2)
}

@Test func blankWhisperContainersRequireWholeRecordingFallback() async {
    let blank = TranscriptionResult(
        text: "",
        segments: [],
        language: "en",
        timings: TranscriptionTimings()
    )
    let spoken = TranscriptionResult(
        text: "Hello",
        segments: [TranscriptionSegment(start: 0, end: 1, text: "Hello")],
        language: "en",
        timings: TranscriptionTimings()
    )

    #expect(!WhisperKitMeetingTranscriber.hasUsableTranscript([blank]))
    #expect(WhisperKitMeetingTranscriber.hasUsableTranscript([spoken]))
    #expect(!WhisperKitMeetingTranscriber.allUtterancesHaveUsableTranscript([
        [spoken],
        [blank],
    ]))
    #expect(WhisperKitMeetingTranscriber.allUtterancesHaveUsableTranscript([
        [spoken],
        [spoken],
    ]))
    let automaticOptions = WhisperKitMeetingTranscriber.decodingOptions(languageCode: nil)
    #expect(automaticOptions.promptTokens == nil)
    #expect(automaticOptions.detectLanguage)
    #expect(automaticOptions.chunkingStrategy == .vad)
    #expect(automaticOptions.task == .transcribe)
    #expect(automaticOptions.wordTimestamps)
    let forcedHindiOptions = WhisperKitMeetingTranscriber.decodingOptions(languageCode: "hi")
    #expect(forcedHindiOptions.promptTokens == nil)
    #expect(!forcedHindiOptions.detectLanguage)
    #expect(forcedHindiOptions.language == "hi")
    #expect(WhisperKitMeetingTranscriber.isolatedDecodeRange(
        coreRange: 400..<600,
        audioCount: 1_000,
        sampleRate: 100
    ) == 380..<620)
    #expect(WhisperKitMeetingTranscriber.isolatedDecodeRange(
        coreRange: 0..<100,
        audioCount: 1_000,
        sampleRate: 100
    ) == 0..<120)

    let gate = TranscriptionAttemptGate()
    let firstAttempt = gate.beginAttempt()
    #expect(gate.isCurrent(firstAttempt))
    let secondAttempt = gate.beginAttempt()
    #expect(!gate.isCurrent(firstAttempt))
    #expect(gate.isCurrent(secondAttempt))
    let probe = TranscriptionDeliveryProbe()
    #expect(gate.schedule(attempt: secondAttempt) {
        await probe.record()
    })
    await gate.invalidateAndDrain()
    #expect(!gate.isCurrent(secondAttempt))
    let countAfterDrain = await probe.count
    await Task.yield()
    #expect(await probe.count == countAfterDrain)
}

private actor TranscriptionDeliveryProbe {
    private(set) var count = 0

    func record() {
        count += 1
    }
}
