import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

@Test func pipelineNodesStayOrderedAndProjectTheActiveStage() {
    let idle = MeetingPipelineNode.project(stage: nil)
    #expect(idle.map(\.kind) == [.audio, .staging, .whisper, .speakers, .vault, .recall])
    #expect(idle.allSatisfy { $0.state == .idle })

    let transcribing = MeetingPipelineNode.project(stage: .transcribing)
    #expect(transcribing.first { $0.kind == .audio }?.state == .complete)
    #expect(transcribing.first { $0.kind == .staging }?.state == .complete)
    #expect(transcribing.first { $0.kind == .whisper }?.state == .active)
    #expect(transcribing.first { $0.kind == .speakers }?.state == .idle)

    let ready = MeetingPipelineNode.project(stage: .ready)
    #expect(ready.allSatisfy { $0.state == .complete })
}

@Test func diagnosticsUseFriendlyAppRelativeLocations() {
    let value = MeetingEngineDiagnostics(
        transcriptionModel: "large-v3",
        diarizationModel: "Pyannote",
        transcriptionModelState: .cached,
        modelCacheLocation: "OpenLoop data / Models / WhisperKit",
        stagingLocation: "OpenLoop data / Meeting Staging"
    )

    #expect(value.processingLocation == "On this Mac")
    #expect(!value.modelCacheLocation.contains("/Users/"))
    #expect(!value.stagingLocation.contains("/Users/"))
}

@Test func IndianMeetingLanguagesMapToWhisperLanguageTokens() {
    #expect(MeetingLanguagePreference.automatic.languageCode == nil)
    #expect(MeetingLanguagePreference.hindiHinglish.languageCode == "hi")
    #expect(MeetingLanguagePreference.bengali.languageCode == "bn")
    #expect(MeetingLanguagePreference.marathi.languageCode == "mr")
    #expect(MeetingLanguagePreference.tamil.languageCode == "ta")
    #expect(MeetingLanguagePreference.telugu.languageCode == "te")
    #expect(MeetingLanguagePreference.urdu.languageCode == "ur")
    #expect(Set(MeetingLanguagePreference.allCases.compactMap(\.languageCode)).count == 15)
}

@Test func eventHistoryDeduplicatesProgressBucketsAndStaysBounded() {
    var history = MeetingPipelineEventHistory(limit: 4)
    history.record(stage: .transcribing, message: "Starting", fraction: 0.01)
    history.record(stage: .transcribing, message: "Same bucket", fraction: 0.09)
    #expect(history.values.count == 1)

    for index in 1...8 {
        history.record(
            stage: index.isMultiple(of: 2) ? .transcribing : .diarizing,
            message: "Event \(index)",
            fraction: Double(index) / 10
        )
    }
    #expect(history.values.count == 4)
    #expect(history.values.last?.message == "Event 8")
}
