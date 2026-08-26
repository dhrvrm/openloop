import ADHDCore

enum StatusMenuCommand: CaseIterable, Equatable, Sendable {
    case openOpenLoop
    case voiceNote
    case voiceTyping
    case keepListening
    case quit
}

struct StatusMenuPresentation: Equatable, Sendable {
    let statusTitle: String
    let statusSymbolName: String
    let openTitle: String
    let voiceNoteTitle: String
    let voiceNoteEnabled: Bool
    let voiceTypingTitle: String
    let voiceTypingEnabled: Bool
    let keepListeningTitle: String
    let keepListeningEnabled: Bool
    let quitTitle: String

    static func make(
        job: MeetingJobPresentation,
        isSystemDictationActive: Bool,
        isDeliveringDictation: Bool,
        keepListeningEnabled: Bool
    ) -> Self {
        let isRecording = job.stage == .recording
        let isVoiceTyping = isRecording
            && isSystemDictationActive
            && job.capturePurpose == .dictation
        let isVoiceNote = isRecording
            && !isVoiceTyping
            && job.capturePurpose == .meeting
        let isProcessing = job.isActive && !isRecording
        let isIdle = !isRecording && !isProcessing && !isDeliveringDictation

        let status: (title: String, symbol: String)
        if isDeliveringDictation {
            status = ("Writing", "text.cursor")
        } else if isVoiceTyping {
            status = ("Typing", "waveform.circle.fill")
        } else if isVoiceNote {
            status = ("Listening", "record.circle.fill")
        } else if isProcessing || isSystemDictationActive {
            status = ("Transcribing", "ellipsis.circle")
        } else {
            status = ("", "circle.circle")
        }

        return Self(
            statusTitle: status.title,
            statusSymbolName: status.symbol,
            openTitle: "Open OpenLoop",
            voiceNoteTitle: isVoiceNote ? "Stop Voice Note" : "Start Voice Note",
            voiceNoteEnabled: isVoiceNote || isIdle,
            voiceTypingTitle: isVoiceTyping ? "Stop Voice Typing" : "Type by Voice",
            voiceTypingEnabled: isVoiceTyping || isIdle,
            keepListeningTitle: "Keep Listening",
            keepListeningEnabled: keepListeningEnabled,
            quitTitle: "Quit OpenLoop"
        )
    }
}
