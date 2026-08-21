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

@MainActor
protocol VoiceDictationCoordinating: AnyObject {
    func deliver(rawText: String, mode: VoiceMode) async -> VoiceDictationDelivery
}

@MainActor
final class VoiceDictationCoordinator: VoiceDictationCoordinating {
    private let processor: LocalSpeechProcessor
    private let contextEngine: VoiceContextEngine
    private let output: TextOutputAdapter

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
            return delivery(
                processed,
                context: context,
                outputRoute: nil,
                state: .awaitingConfirmation
            )
        }

        let outputResult = output.insert(processed.outputText)
        return delivery(
            processed,
            context: context,
            outputRoute: outputResult.route,
            state: outputResult.inserted ? .inserted : .failed
        )
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
