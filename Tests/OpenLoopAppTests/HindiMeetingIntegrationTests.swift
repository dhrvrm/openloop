import Foundation
import Testing
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

    let transcriber = WhisperKitMeetingTranscriber(
        modelIdentifier: modelIdentifier,
        modelStorageURL: URL(fileURLWithPath: modelStoragePath, isDirectory: true),
        speakerDiarizationEnabled: false
    )
    let output = try await transcriber.transcribe(
        audioURL: URL(fileURLWithPath: fixturePath),
        languageCode: languageCode
    ) { _ in }
    let text = output.segments.map(\.text).joined(separator: " ")
    let devanagariCount = text.unicodeScalars.filter {
        (0x0900...0x097F).contains(Int($0.value))
    }.count

    print("hindi-detected-language=\(output.detectedLanguage ?? "none")")
    print("hindi-output-characters=\(text.count)")
    print("hindi-devanagari-scalars=\(devanagariCount)")
    print("hindi-synthetic-output=\(text)")
    #expect(output.detectedLanguage == "hi")
    #expect(devanagariCount >= 20)
    #expect(text.contains("मीटिंग"))
    #expect(text.contains("प्रोजेक्ट") || text.contains("प्रजेक्ट"))
}
