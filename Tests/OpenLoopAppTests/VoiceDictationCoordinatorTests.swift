import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

private actor DictationEditorProbe: LocalTextEditing {
    private(set) var requests: [VoiceProcessingRequest] = []

    func edit(_ request: VoiceProcessingRequest, text: String) async throws -> String {
        requests.append(request)
        return "Hello, Dhruv."
    }
}

@MainActor
private final class DictationContextReader: VoiceContextReading {
    func read() -> VoiceContextSnapshot {
        VoiceContextSnapshot(
            applicationIdentifier: "com.apple.TextEdit",
            applicationName: "TextEdit",
            focusedRole: "AXTextArea",
            selectedText: "selected release note",
            surroundingText: "Release notes for SGLC",
            capturedAt: Date(timeIntervalSince1970: 1)
        )
    }
}

@MainActor
private final class DictationAccessibilityInserter: AccessibilityTextInserting {
    var inserted: [String] = []

    func insert(_ text: String) -> Bool {
        inserted.append(text)
        return true
    }
}

@MainActor
private final class RejectingClipboardPaster: ClipboardTextPasting {
    func paste(_ text: String) -> Bool { false }
}

@MainActor
private final class RejectingKeyboardTyper: KeyboardTextTyping {
    func type(_ text: String) -> Bool { false }
}

@MainActor
@Test func dictationCoordinatorProcessesConsentedContextAndInsertsThroughAccessibility() async {
    let editor = DictationEditorProbe()
    let inserter = DictationAccessibilityInserter()
    let coordinator = VoiceDictationCoordinator(
        processor: LocalSpeechProcessor(compactEditor: editor),
        contextEngine: VoiceContextEngine(reader: DictationContextReader(), isConsented: { true }),
        output: TextOutputAdapter(
            accessibility: inserter,
            clipboard: RejectingClipboardPaster(),
            keyboard: RejectingKeyboardTyper()
        )
    )

    let delivery = await coordinator.deliver(rawText: "hello Dhruv", mode: .polished)

    #expect(delivery.rawText == "hello Dhruv")
    #expect(delivery.processedText == "Hello, Dhruv.")
    #expect(delivery.processingRoute == .compactLocalEditor)
    #expect(delivery.outputRoute == .accessibility)
    #expect(delivery.state == .inserted)
    #expect(delivery.applicationName == "TextEdit")
    #expect(inserter.inserted == ["Hello, Dhruv."])
    let request = await editor.requests.first
    #expect(request?.applicationIdentifier == "com.apple.TextEdit")
    #expect(request?.selectedText == "selected release note")
    #expect(request?.surroundingText == "Release notes for SGLC")
}

@MainActor
@Test func dictationCoordinatorDoesNotExecuteCommandsThatRequireConfirmation() async {
    let inserter = DictationAccessibilityInserter()
    let coordinator = VoiceDictationCoordinator(
        processor: LocalSpeechProcessor(),
        contextEngine: VoiceContextEngine(reader: DictationContextReader(), isConsented: { true }),
        output: TextOutputAdapter(
            accessibility: inserter,
            clipboard: RejectingClipboardPaster(),
            keyboard: RejectingKeyboardTyper()
        )
    )

    let delivery = await coordinator.deliver(
        rawText: "voice command delete selection",
        mode: .raw
    )

    #expect(delivery.state == .awaitingConfirmation)
    #expect(delivery.command == .deleteSelection)
    #expect(delivery.outputRoute == nil)
    #expect(inserter.inserted.isEmpty)
}
