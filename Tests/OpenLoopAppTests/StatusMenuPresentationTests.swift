import ADHDCore
import Testing
@testable import OpenLoopApp

@Test func statusMenuContainsOnlyImmediateVoiceControls() {
    #expect(StatusMenuCommand.allCases == [
        .openOpenLoop,
        .voiceNote,
        .voiceTyping,
        .keepListening,
        .quit,
    ])

    let presentation = StatusMenuPresentation.make(
        job: MeetingJobPresentation(),
        isSystemDictationActive: false,
        isDeliveringDictation: false,
        keepListeningEnabled: false
    )
    let visibleCopy = [
        presentation.openTitle,
        presentation.voiceNoteTitle,
        presentation.voiceTypingTitle,
        presentation.keepListeningTitle,
        presentation.quitTitle,
    ].joined(separator: " ")

    for legacyTerm in ["Capture", "Now", "Pause", "Context", "Emerging", "Ask", "Act"] {
        #expect(!visibleCopy.contains(legacyTerm))
    }
}

@Test func idleStatusMenuUsesPlainStartActions() {
    let presentation = StatusMenuPresentation.make(
        job: MeetingJobPresentation(),
        isSystemDictationActive: false,
        isDeliveringDictation: false,
        keepListeningEnabled: false
    )

    #expect(presentation.statusTitle.isEmpty)
    #expect(presentation.statusSymbolName == "circle.circle")
    #expect(presentation.openTitle == "Open OpenLoop")
    #expect(presentation.voiceNoteTitle == "Start Voice Note")
    #expect(presentation.voiceNoteEnabled)
    #expect(presentation.voiceTypingTitle == "Type by Voice")
    #expect(presentation.voiceTypingEnabled)
    #expect(presentation.keepListeningTitle == "Keep Listening")
    #expect(!presentation.keepListeningEnabled)
    #expect(presentation.quitTitle == "Quit OpenLoop")
}

@Test func voiceNoteRecordingShowsListeningAndStopsOnlyTheActiveMode() {
    let presentation = StatusMenuPresentation.make(
        job: MeetingJobPresentation(
            stage: .recording,
            capturePurpose: .meeting
        ),
        isSystemDictationActive: false,
        isDeliveringDictation: false,
        keepListeningEnabled: true
    )

    #expect(presentation.statusTitle == "Listening")
    #expect(presentation.statusSymbolName == "record.circle.fill")
    #expect(presentation.voiceNoteTitle == "Stop Voice Note")
    #expect(presentation.voiceNoteEnabled)
    #expect(presentation.voiceTypingTitle == "Type by Voice")
    #expect(!presentation.voiceTypingEnabled)
    #expect(presentation.keepListeningEnabled)
}

@Test func voiceTypingShowsTypingAndStopsOnlyTheActiveMode() {
    let presentation = StatusMenuPresentation.make(
        job: MeetingJobPresentation(
            stage: .recording,
            capturePurpose: .dictation
        ),
        isSystemDictationActive: true,
        isDeliveringDictation: false,
        keepListeningEnabled: false
    )

    #expect(presentation.statusTitle == "Typing")
    #expect(presentation.statusSymbolName == "waveform.circle.fill")
    #expect(presentation.voiceNoteTitle == "Start Voice Note")
    #expect(!presentation.voiceNoteEnabled)
    #expect(presentation.voiceTypingTitle == "Stop Voice Typing")
    #expect(presentation.voiceTypingEnabled)
}

@Test func activeRecognitionShowsTranscribingAndPreventsOverlappingCapture() {
    let presentation = StatusMenuPresentation.make(
        job: MeetingJobPresentation(stage: .transcribing),
        isSystemDictationActive: false,
        isDeliveringDictation: false,
        keepListeningEnabled: false
    )

    #expect(presentation.statusTitle == "Transcribing")
    #expect(presentation.statusSymbolName == "ellipsis.circle")
    #expect(!presentation.voiceNoteEnabled)
    #expect(!presentation.voiceTypingEnabled)
}

@Test func dictationDeliveryShowsWritingUntilInsertionFinishes() {
    let presentation = StatusMenuPresentation.make(
        job: MeetingJobPresentation(stage: .ready),
        isSystemDictationActive: true,
        isDeliveringDictation: true,
        keepListeningEnabled: false
    )

    #expect(presentation.statusTitle == "Writing")
    #expect(presentation.statusSymbolName == "text.cursor")
    #expect(!presentation.voiceNoteEnabled)
    #expect(!presentation.voiceTypingEnabled)
}
