import ADHDCore
import Foundation

enum VoiceDictationDeliveryState: String, Equatable, Sendable {
    case inserted
    case awaitingConfirmation
    case failed
}

struct VoiceDictationDelivery: Equatable, Sendable {
    let rawText: String
    let processedText: String
    let mode: VoiceMode
    let processingRoute: VoiceProcessingRoute
    let outputRoute: TextOutputRoute?
    let state: VoiceDictationDeliveryState
    let command: VoiceCommand?
    let applicationName: String?
    let meaningPreserved: Bool

    var statusMessage: String {
        switch state {
        case .inserted:
            if let command {
                return "Executed \(command.displayName) in \(applicationName ?? "the active app")."
            }
            let destination = applicationName.map { " into \($0)" } ?? ""
            let route = outputRoute?.displayName ?? "local output"
            return "Inserted\(destination) using \(route)."
        case .awaitingConfirmation:
            return "This voice command can change existing content and needs confirmation."
        case .failed:
            return "The transcript is safe in OpenLoop, but no active text field accepted it."
        }
    }
}

extension TextOutputRoute {
    var displayName: String {
        switch self {
        case .accessibility: "Accessibility"
        case .clipboardPaste: "clipboard paste"
        case .simulatedKeyboard: "keyboard typing"
        case .unavailable: "no available route"
        }
    }
}

extension VoiceCommand {
    var displayName: String {
        switch self {
        case .newLine: "new line"
        case .newParagraph: "new paragraph"
        case .undo: "undo"
        case .deleteSelection: "delete selection"
        case .submit: "submit"
        }
    }
}

@MainActor
protocol VoiceDictationCoordinating: AnyObject {
    func deliver(rawText: String, mode: VoiceMode) async -> VoiceDictationDelivery
    func confirmPendingCommand() -> VoiceDictationDelivery?
    func discardPendingCommand()
    func undoLastOutput() -> TextOutputResult
}

@MainActor
final class VoiceDictationCoordinator: VoiceDictationCoordinating {
    private let processor: LocalSpeechProcessor
    private let contextEngine: VoiceContextEngine
    private let output: TextOutputAdapter
    private var pendingCommand: (VoiceProcessingResult, VoiceContextSnapshot?)?

    init(
        processor: LocalSpeechProcessor,
        contextEngine: VoiceContextEngine,
        output: TextOutputAdapter
    ) {
        self.processor = processor
        self.contextEngine = contextEngine
        self.output = output
    }

    func deliver(rawText: String, mode: VoiceMode) async -> VoiceDictationDelivery {
        let context = contextEngine.snapshot()
        let request = VoiceProcessingRequest(
            rawText: rawText,
            mode: mode,
            applicationIdentifier: context?.applicationIdentifier,
            selectedText: context?.selectedText,
            surroundingText: context?.surroundingText
        )
        let processed = await processor.process(request)

        if processed.command?.requiresConfirmation == true {
            pendingCommand = (processed, context)
            return delivery(
                processed,
                context: context,
                outputRoute: nil,
                state: .awaitingConfirmation
            )
        }

        pendingCommand = nil
        let outputResult = if let command = processed.command {
            output.perform(command)
        } else {
            output.insert(processed.outputText)
        }
        return delivery(
            processed,
            context: context,
            outputRoute: outputResult.route,
            state: outputResult.inserted ? .inserted : .failed
        )
    }

    func confirmPendingCommand() -> VoiceDictationDelivery? {
        guard let (processed, context) = pendingCommand,
              let command = processed.command,
              command.requiresConfirmation
        else { return nil }
        pendingCommand = nil
        let result = output.perform(command)
        return delivery(
            processed,
            context: context,
            outputRoute: result.route,
            state: result.inserted ? .inserted : .failed
        )
    }

    func discardPendingCommand() {
        pendingCommand = nil
    }

    func undoLastOutput() -> TextOutputResult {
        output.perform(.undo)
    }

    private func delivery(
        _ processed: VoiceProcessingResult,
        context: VoiceContextSnapshot?,
        outputRoute: TextOutputRoute?,
        state: VoiceDictationDeliveryState
    ) -> VoiceDictationDelivery {
        VoiceDictationDelivery(
            rawText: processed.rawText,
            processedText: processed.outputText,
            mode: processed.mode,
            processingRoute: processed.route,
            outputRoute: outputRoute,
            state: state,
            command: processed.command,
            applicationName: context?.applicationName,
            meaningPreserved: processed.meaningPreserved
        )
    }
}
