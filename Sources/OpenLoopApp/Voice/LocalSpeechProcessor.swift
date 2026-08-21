import ADHDCore
import Foundation

protocol LocalTextEditing: Sendable {
    func edit(_ request: VoiceProcessingRequest, text: String) async throws -> String
}

struct MeaningPreservationValidator {
    func preservesMeaning(source: String, candidate: String) -> Bool {
        let candidateKey = Self.key(candidate)
        guard !candidateKey.isEmpty else { return false }
        let anchors = Self.anchors(in: source)
        return anchors.allSatisfy { candidateKey.contains(Self.key($0)) }
    }

    private static func anchors(in text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { token in
            token.contains(where: \.isNumber)
                || token.count >= 2 && token.allSatisfy { $0.isUppercase || $0.isNumber }
                || token.first?.isUppercase == true && token.dropFirst().contains(where: \.isLowercase)
                || token.unicodeScalars.contains(where: { (0x0900...0x097F).contains($0.value) })
        }
    }

    private static func key(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

struct LocalSpeechProcessor: Sendable {
    private let router: LocalIntentRouter
    private let compactEditor: (any LocalTextEditing)?
    private let largeEditor: (any LocalTextEditing)?
    private let normalizationRules: @Sendable () async -> [TranscriptionNormalizationRule]
    private let validator: MeaningPreservationValidator

    init(
        router: LocalIntentRouter = LocalIntentRouter(),
        compactEditor: (any LocalTextEditing)? = nil,
        largeEditor: (any LocalTextEditing)? = nil,
        normalizationRules: @escaping @Sendable () async -> [TranscriptionNormalizationRule] = { [] },
        validator: MeaningPreservationValidator = MeaningPreservationValidator()
    ) {
        self.router = router
        self.compactEditor = compactEditor
        self.largeEditor = largeEditor
        self.normalizationRules = normalizationRules
        self.validator = validator
    }

    func process(_ request: VoiceProcessingRequest) async -> VoiceProcessingResult {
        let raw = request.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = DeterministicTranscriptNormalizer.apply(
            await normalizationRules(),
            to: raw
        )
        switch router.route(request) {
        case .direct:
            return VoiceProcessingResult(
                rawText: raw,
                outputText: normalized,
                mode: request.mode,
                route: .direct
            )
        case .command(let command):
            return VoiceProcessingResult(
                rawText: raw,
                outputText: Self.output(for: command),
                mode: request.mode,
                route: .deterministicCommand,
                command: command
            )
        case .compactEditor:
            return await edit(
                request,
                normalized: normalized,
                editor: compactEditor,
                route: .compactLocalEditor
            )
        case .largeEditor:
            return await edit(
                request,
                normalized: normalized,
                editor: largeEditor,
                route: .largeLocalEditor
            )
        }
    }

    private func edit(
        _ request: VoiceProcessingRequest,
        normalized: String,
        editor: (any LocalTextEditing)?,
        route: VoiceProcessingRoute
    ) async -> VoiceProcessingResult {
        guard let editor,
              let candidate = try? await editor.edit(request, text: normalized)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              validator.preservesMeaning(source: normalized, candidate: candidate)
        else {
            return VoiceProcessingResult(
                rawText: request.rawText,
                outputText: normalized,
                mode: request.mode,
                route: .rawFallback,
                meaningPreserved: false
            )
        }
        return VoiceProcessingResult(
            rawText: request.rawText,
            outputText: candidate,
            mode: request.mode,
            route: route
        )
    }

    private static func output(for command: VoiceCommand) -> String {
        switch command {
        case .newLine: "\n"
        case .newParagraph: "\n\n"
        case .undo, .deleteSelection, .submit: ""
        }
    }
}
