import Foundation

public enum VoiceMode: String, Codable, CaseIterable, Sendable {
    case raw
    case polished
    case code
    case email
    case casual
    case markdown
    case bullets
    case json
}

public enum VoiceCommand: Equatable, Sendable {
    case newLine
    case newParagraph
    case undo
    case deleteSelection
    case submit

    public var requiresConfirmation: Bool {
        switch self {
        case .deleteSelection, .submit: true
        case .newLine, .newParagraph, .undo: false
        }
    }
}

public enum VoiceProcessingRoute: String, Codable, Equatable, Sendable {
    case direct
    case deterministicCommand
    case compactLocalEditor
    case largeLocalEditor
    case rawFallback
}

public struct VoiceProcessingRequest: Equatable, Sendable {
    public let rawText: String
    public let mode: VoiceMode
    public let applicationIdentifier: String?
    public let selectedText: String?
    public let surroundingText: String?

    public init(
        rawText: String,
        mode: VoiceMode,
        applicationIdentifier: String? = nil,
        selectedText: String? = nil,
        surroundingText: String? = nil
    ) {
        self.rawText = rawText
        self.mode = mode
        self.applicationIdentifier = applicationIdentifier
        self.selectedText = selectedText
        self.surroundingText = surroundingText
    }
}

public struct VoiceProcessingResult: Equatable, Sendable {
    public let rawText: String
    public let outputText: String
    public let mode: VoiceMode
    public let route: VoiceProcessingRoute
    public let command: VoiceCommand?
    public let meaningPreserved: Bool

    public init(
        rawText: String,
        outputText: String,
        mode: VoiceMode,
        route: VoiceProcessingRoute,
        command: VoiceCommand? = nil,
        meaningPreserved: Bool = true
    ) {
        self.rawText = rawText
        self.outputText = outputText
        self.mode = mode
        self.route = route
        self.command = command
        self.meaningPreserved = meaningPreserved
    }
}
