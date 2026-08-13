import Foundation
import Testing
@testable import ADHDCore

@Test func intentionSupportsInterruptionAndReturn() throws {
    var intention = Intention(
        id: UUID(),
        sourceCaptureID: UUID(),
        desiredOutcome: "Send Riya the revised flow",
        nextAction: "Open the latest Figma link",
        state: .open,
        createdAt: Date(timeIntervalSince1970: 10),
        returnPacket: nil
    )

    try intention.transition(to: .active)
    let packet = try ReturnPacket(
        capturedAt: Date(timeIntervalSince1970: 20),
        justCompleted: "Found the correct design file",
        nextAction: "Copy its link into the message",
        blocker: nil,
        references: ["https://figma.example/design"]
    )
    try intention.interrupt(with: packet)
    #expect(intention.state == .interrupted)
    #expect(intention.returnPacket == packet)

    try intention.resume()
    #expect(intention.state == .active)
    #expect(intention.nextAction == "Copy its link into the message")

    try intention.transition(to: .closed)
    #expect(intention.state == .closed)
}

@Test func closedIntentionCannotRestart() throws {
    var intention = Intention(
        id: UUID(),
        sourceCaptureID: UUID(),
        desiredOutcome: "Archive the note",
        nextAction: "Move the note to Archive",
        state: .open,
        createdAt: .now,
        returnPacket: nil
    )
    try intention.transition(to: .closed)

    #expect(throws: IntentionError.invalidTransition(from: .closed, to: .active)) {
        try intention.transition(to: .active)
    }
}

@Test func returnPacketRequiresANextAction() {
    #expect(throws: IntentionError.emptyNextAction) {
        try ReturnPacket(
            capturedAt: .now,
            justCompleted: nil,
            nextAction: "  ",
            blocker: nil,
            references: []
        )
    }
}
