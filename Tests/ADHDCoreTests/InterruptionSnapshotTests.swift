import Foundation
import Testing
@testable import ADHDCore

private struct FixedContextProvider: ContextReferenceProvider {
    let values: [String]

    func references() async throws -> [String] { values }
}

private struct FailingContextProvider: ContextReferenceProvider {
    struct Failure: Error {}

    func references() async throws -> [String] { throw Failure() }
}

@Test func compositeContextProviderKeepsSuccessfulEvidenceWhenAnotherProviderFails() async throws {
    let provider = CompositeContextReferenceProvider([
        FailingContextProvider(),
        FixedContextProvider(values: ["Context trail — Xcode → Safari"]),
    ])

    #expect(try await provider.references() == ["Context trail — Xcode → Safari"])
}

@Test func interruptionComposerNormalizesTextAndDeduplicatesReferences() async throws {
    let composer = InterruptionSnapshotComposer(
        contextProvider: FixedContextProvider(values: [" Notes ", "https://example.test", ""])
    )
    let capturedAt = Date(timeIntervalSince1970: 42)
    let draft = InterruptionDraft(
        justCompleted: "  Opened the brief  ",
        nextAction: "  Write the first paragraph  ",
        blocker: "   ",
        references: ["Notes", " /tmp/brief.md ", "Notes"]
    )

    let packet = try await composer.compose(draft, at: capturedAt)

    #expect(packet.capturedAt == capturedAt)
    #expect(packet.justCompleted == "Opened the brief")
    #expect(packet.nextAction == "Write the first paragraph")
    #expect(packet.blocker == nil)
    #expect(packet.references == ["Notes", "/tmp/brief.md", "https://example.test"])
}

@Test func interruptionComposerKeepsManualReferencesWhenContextFails() async throws {
    let composer = InterruptionSnapshotComposer(contextProvider: FailingContextProvider())
    let draft = InterruptionDraft(
        justCompleted: nil,
        nextAction: "Resume here",
        blocker: nil,
        references: ["local note"]
    )

    let packet = try await composer.compose(draft, at: .now)

    #expect(packet.references == ["local note"])
}

@Test func interruptionComposerRejectsAnEmptyNextAction() async {
    let composer = InterruptionSnapshotComposer()
    let draft = InterruptionDraft(
        justCompleted: nil,
        nextAction: " \n ",
        blocker: nil,
        references: []
    )

    await #expect(throws: IntentionError.emptyNextAction) {
        try await composer.compose(draft, at: .now)
    }
}
