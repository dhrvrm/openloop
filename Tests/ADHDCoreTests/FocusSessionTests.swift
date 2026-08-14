import Foundation
import Testing
@testable import ADHDCore

private let intentionID = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000222")!
private let start = Date(timeIntervalSince1970: 1_000)

@Test func focusSessionStartsActiveAndReportsCalmElapsedTime() {
    let session = FocusSession(id: sessionID, intentionID: intentionID, startedAt: start)

    #expect(session.state == .active)
    #expect(session.activeSince == start)
    #expect(session.elapsed(at: start.addingTimeInterval(75)) == 75)
}

@Test func pauseAccruesTimeAndContinueStartsANewActiveInterval() throws {
    var session = FocusSession(id: sessionID, intentionID: intentionID, startedAt: start)

    try session.pause(at: start.addingTimeInterval(30))
    #expect(session.state == .paused)
    #expect(session.elapsed(at: start.addingTimeInterval(300)) == 30)

    try session.continueSession(at: start.addingTimeInterval(100))
    #expect(session.state == .active)
    #expect(session.elapsed(at: start.addingTimeInterval(145)) == 75)
}

@Test func interruptionCanSnapshotActiveOrPausedFocus() throws {
    var active = FocusSession(id: sessionID, intentionID: intentionID, startedAt: start)
    try active.interrupt(at: start.addingTimeInterval(40))
    #expect(active.state == .interrupted)
    #expect(active.elapsed(at: start.addingTimeInterval(500)) == 40)

    var paused = FocusSession(id: UUID(), intentionID: intentionID, startedAt: start)
    try paused.pause(at: start.addingTimeInterval(20))
    try paused.interrupt(at: start.addingTimeInterval(80))
    #expect(paused.state == .interrupted)
    #expect(paused.elapsed(at: start.addingTimeInterval(500)) == 20)
}

@Test func interruptedFocusCanResumeAndThenFinish() throws {
    var session = FocusSession(id: sessionID, intentionID: intentionID, startedAt: start)
    try session.interrupt(at: start.addingTimeInterval(10))
    try session.resume(at: start.addingTimeInterval(20))
    try session.finish(at: start.addingTimeInterval(35))

    #expect(session.state == .finished)
    #expect(session.elapsed(at: start.addingTimeInterval(1_000)) == 25)
}

@Test func finishingPausedFocusDoesNotAddPausedTime() throws {
    var session = FocusSession(id: sessionID, intentionID: intentionID, startedAt: start)
    try session.pause(at: start.addingTimeInterval(12))
    try session.finish(at: start.addingTimeInterval(500))

    #expect(session.state == .finished)
    #expect(session.elapsed(at: start.addingTimeInterval(800)) == 12)
}

@Test func backwardClockMovementNeverSubtractsElapsedTime() throws {
    var session = FocusSession(id: sessionID, intentionID: intentionID, startedAt: start)

    #expect(session.elapsed(at: start.addingTimeInterval(-10)) == 0)
    try session.pause(at: start.addingTimeInterval(-10))
    #expect(session.accumulatedSeconds == 0)
}

@Test func invalidFocusTransitionsAreRejectedWithoutMutation() throws {
    var session = FocusSession(id: sessionID, intentionID: intentionID, startedAt: start)
    try session.pause(at: start.addingTimeInterval(10))

    #expect(throws: FocusSessionError.invalidTransition(from: .paused, to: .paused)) {
        try session.pause(at: start.addingTimeInterval(20))
    }
    #expect(session.state == .paused)
}
