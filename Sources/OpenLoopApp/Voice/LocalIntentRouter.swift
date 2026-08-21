import ADHDCore
import Foundation

enum LocalIntentDecision: Equatable {
    case direct
    case command(VoiceCommand)
    case compactEditor
    case largeEditor
}

struct LocalIntentRouter {
    let difficultWordThreshold: Int

    init(difficultWordThreshold: Int = 80) {
        self.difficultWordThreshold = difficultWordThreshold
    }

    func route(_ request: VoiceProcessingRequest) -> LocalIntentDecision {
        let normalized = request.rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let command = Self.command(for: normalized) { return .command(command) }
        if request.mode == .raw { return .direct }
        if Self.requestsTransformation(normalized)
            || Self.wordCount(normalized) > difficultWordThreshold {
            return .largeEditor
        }
        return .compactEditor
    }

    private static func command(for text: String) -> VoiceCommand? {
        switch text {
        case "voice command new line": .newLine
        case "voice command new paragraph": .newParagraph
        case "voice command undo": .undo
        case "voice command delete selection": .deleteSelection
        case "voice command submit": .submit
        default: nil
        }
    }

    private static func requestsTransformation(_ text: String) -> Bool {
        [
            "rewrite this as", "summarize this", "turn this into",
            "restructure this", "compare these", "explain this",
        ].contains { text.contains($0) }
    }

    private static func wordCount(_ text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }
}
