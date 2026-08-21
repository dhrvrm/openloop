import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

private actor EditorProbe: LocalTextEditing {
    private let output: String
    private var inputs: [String] = []

    init(output: String) { self.output = output }

    func edit(_ request: VoiceProcessingRequest, text: String) async throws -> String {
        inputs.append(text)
        return output
    }

    func callCount() -> Int { inputs.count }
}

@Test func rawDictationBypassesEditorsButAppliesRepeatedDeterministicRules() async {
    let editor = EditorProbe(output: "should not run")
    let rule = TranscriptionNormalizationRule(
        recognized: "ex code",
        corrected: "Xcode",
        scope: .programming,
        projectIdentifier: nil,
        evidenceCount: 2
    )
    let processor = LocalSpeechProcessor(
        compactEditor: editor,
        largeEditor: editor,
        normalizationRules: { [rule] }
    )

    let result = await processor.process(VoiceProcessingRequest(
        rawText: "Open ex code",
        mode: .raw
    ))

    #expect(result.outputText == "Open Xcode")
    #expect(result.route == .direct)
    #expect(await editor.callCount() == 0)
}

@Test func explicitVoiceCommandsAreDeterministicAndDestructiveOnesRequireConfirmation() async {
    let processor = LocalSpeechProcessor()
    let newline = await processor.process(VoiceProcessingRequest(
        rawText: "voice command new paragraph",
        mode: .polished
    ))
    let deletion = await processor.process(VoiceProcessingRequest(
        rawText: "voice command delete selection",
        mode: .raw
    ))

    #expect(newline.route == .deterministicCommand)
    #expect(newline.command == .newParagraph)
    #expect(newline.outputText == "\n\n")
    #expect(deletion.command == .deleteSelection)
    #expect(deletion.command?.requiresConfirmation == true)
}

@Test func routineFormattingUsesCompactEditorAndDifficultTransformationUsesLargeEditor() async {
    let compact = EditorProbe(output: "Hello, Dhruv.")
    let large = EditorProbe(output: "- Dhruv: First\n- Second")
    let processor = LocalSpeechProcessor(compactEditor: compact, largeEditor: large)

    let routine = await processor.process(VoiceProcessingRequest(
        rawText: "hello Dhruv",
        mode: .polished
    ))
    let difficult = await processor.process(VoiceProcessingRequest(
        rawText: "turn this into bullets Dhruv first second",
        mode: .bullets
    ))

    #expect(routine.route == .compactLocalEditor)
    #expect(routine.outputText == "Hello, Dhruv.")
    #expect(difficult.route == .largeLocalEditor)
    #expect(difficult.outputText == "- Dhruv: First\n- Second")
    #expect(await compact.callCount() == 1)
    #expect(await large.callCount() == 1)
}

@Test func rewriteThatDropsNamesOrNumbersFallsBackToRawText() async {
    let unsafeEditor = EditorProbe(output: "The release is soon.")
    let processor = LocalSpeechProcessor(compactEditor: unsafeEditor)

    let result = await processor.process(VoiceProcessingRequest(
        rawText: "Dhruv ships SGLC release 42 tomorrow",
        mode: .email
    ))

    #expect(result.route == .rawFallback)
    #expect(result.outputText == "Dhruv ships SGLC release 42 tomorrow")
    #expect(!result.meaningPreserved)
}

@Test func rewriteThatDropsHindiWordsFallsBackToRawCodeSwitchedText() async {
    let unsafeEditor = EditorProbe(output: "Can we reduce the release time for SGLC releases?")
    let processor = LocalSpeechProcessor(compactEditor: unsafeEditor)

    let result = await processor.process(VoiceProcessingRequest(
        rawText: "वो क्या हम काम कर सकते हैं? Can we reduce the release time for SGLC releases?",
        mode: .polished
    ))

    #expect(result.route == .rawFallback)
    #expect(result.outputText == "वो क्या हम काम कर सकते हैं? Can we reduce the release time for SGLC releases?")
    #expect(!result.meaningPreserved)
}

@Test func allProductModesHaveAnExplicitNonRawEditorRoute() {
    let router = LocalIntentRouter()
    for mode in VoiceMode.allCases where mode != .raw {
        #expect(router.route(VoiceProcessingRequest(rawText: "simple text", mode: mode))
            == .compactEditor)
    }
}
