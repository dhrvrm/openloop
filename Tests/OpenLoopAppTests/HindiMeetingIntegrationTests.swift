import Foundation
import Testing
import WhisperKit
@testable import OpenLoopApp

@Test func localWhisperRecognizesHindiFixture() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let fixturePath = environment["OPENLOOP_HINDI_FIXTURE"],
          let modelStoragePath = environment["OPENLOOP_MODEL_STORAGE"] else {
        return
    }
    let modelIdentifier = environment["OPENLOOP_MODEL_IDENTIFIER"]
        ?? "large-v3-v20240930_626MB"
    let languageCode = environment["OPENLOOP_LANGUAGE_CODE"]
    let expectedName = environment["OPENLOOP_EXPECTED_NAME"]
    let expectsNonemptyOnly = environment["OPENLOOP_EXPECT_NONEMPTY_ONLY"] == "1"
    let expectedLanguages = environment["OPENLOOP_EXPECTED_LANGUAGES"]?
        .split(separator: ",")
        .map(String.init)
    let expectedChunkEvents = environment["OPENLOOP_EXPECTED_CHUNK_EVENTS"]
        .flatMap(Int.init)

    if expectedLanguages?.count ?? 0 > 1 {
        let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: fixturePath)
        #expect(
            UtteranceAudioChunker.ranges(in: audio).count == 1,
            "The acceptance fixture must require language-change planning, not a silence split."
        )
    }

    let transcriber = WhisperKitMeetingTranscriber(
        modelIdentifier: modelIdentifier,
        modelStorageURL: URL(fileURLWithPath: modelStoragePath, isDirectory: true),
        speakerDiarizationEnabled: false
    )
    let progressRecorder = MeetingProgressRecorder()
    let output = try await transcriber.transcribe(
        audioURL: URL(fileURLWithPath: fixturePath),
        languageCode: languageCode
    ) { progress in
        await progressRecorder.record(progress.message)
    }
    let text = output.segments.map(\.text).joined(separator: " ")
    let devanagariCount = text.unicodeScalars.filter {
        (0x0900...0x097F).contains(Int($0.value))
    }.count

    print("hindi-detected-language=\(output.detectedLanguage ?? "none")")
    print("hindi-output-characters=\(text.count)")
    print("hindi-devanagari-scalars=\(devanagariCount)")
    print("hindi-synthetic-output=\(text)")
    print("hindi-progress=\(await progressRecorder.messages)")
    if expectsNonemptyOnly {
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return
    }
    if let expectedLanguages {
        let detectedLanguages = Set(output.detectedLanguage?.components(separatedBy: " + ") ?? [])
        #expect(expectedLanguages.allSatisfy(detectedLanguages.contains))
        let messages = await progressRecorder.messages
        #expect(messages.contains { $0.hasPrefix("Language scan: ") })
        #expect(messages.contains { $0.hasPrefix("Language change found near ") })
        #expect(messages.contains("Detecting each spoken language locally"))
        if let expectedChunkEvents {
            #expect(
                messages.filter { $0 == "Detecting each spoken language locally" }.count
                    == expectedChunkEvents
            )
        }
    } else {
        #expect(output.detectedLanguage == "hi")
    }
    if let expectedName {
        let lowercaseText = text.lowercased()
        #expect(text.localizedCaseInsensitiveContains(expectedName))
        #expect(text.localizedCaseInsensitiveContains("English"))
        #expect(text.contains("हिंदी") || lowercaseText.contains("hindi"))
        #expect(text.contains("बात") || lowercaseText.contains("baat"))
        #expect(text.contains("रहा") || lowercaseText.contains("raha"))
        #expect(devanagariCount >= 10)
        return
    }
    #expect(devanagariCount >= 20)
    #expect(text.contains("मीटिंग") || text.localizedCaseInsensitiveContains("meeting"))
    #expect(
        text.contains("प्रोजेक्ट")
            || text.contains("प्रजेक्ट")
            || text.localizedCaseInsensitiveContains("project")
    )
}

private actor MeetingProgressRecorder {
    private(set) var messages: [String] = []

    func record(_ message: String?) {
        if let message { messages.append(message) }
    }
}
