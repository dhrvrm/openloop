import ADHDCore
import Foundation
import Testing
@testable import LocalStore

@Test func savedThoughtsSurviveRepositoryRestart() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let capture = try RawCapture(createdAt: .now, text: "Email the revised flow")
    let intention = Intention(
        id: UUID(),
        sourceCaptureID: capture.id,
        desiredOutcome: "Riya receives the new flow",
        nextAction: "Open the latest Figma file",
        state: .open,
        createdAt: .now,
        returnPacket: nil
    )

    let writer = try JSONFileThoughtRepository(directory: directory)
    try await writer.save(capture: capture)
    try await writer.save(intention: intention)

    let reader = try JSONFileThoughtRepository(directory: directory)
    #expect(try await reader.intention(id: intention.id) == intention)
    #expect(try await reader.openIntentions() == [intention])
}

@Test func corruptSnapshotIsReportedInsteadOfDiscarded() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not-json".utf8).write(to: directory.appendingPathComponent("thought-loop.json"))

    #expect(throws: JSONFileThoughtRepositoryError.corruptSnapshot) {
        try JSONFileThoughtRepository(directory: directory)
    }
}
