import Foundation
import Testing
@testable import OpenLoopApp

@Suite("v1 reliability")
struct V1ReliabilityTests {
    @Test func unexpectedLaunchIsReportedOnceUntilACleanExit() throws {
        let suite = "dev.openloop.v1-recovery.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = LaunchRecoveryTracker(defaults: defaults, key: "in-progress")

        #expect(tracker.beginLaunch() == false)
        #expect(tracker.beginLaunch())
        tracker.markCleanExit()
        #expect(tracker.beginLaunch() == false)
    }

    @Test func voicePermissionCopyCanRemainActionDriven() {
        let value = CapabilitySummary(
            quickCapture: .ready,
            microphone: .askWhenUsed,
            speechRecognition: .askWhenUsed
        )

        #expect(value.quickCapture == .ready)
        #expect(value.microphone == .askWhenUsed)
        #expect(value.speechRecognition == .askWhenUsed)
    }

    @Test func workspaceOrientationMakesNavigationAndCaptureShortcutsExplicit() {
        #expect(WorkspaceOrientation.destinations.map(\.title) == [
            "Now", "Return", "Later", "Recall",
        ])
        #expect(Set(WorkspaceOrientation.destinations.map(\.icon)).count == 4)
        #expect(WorkspaceOrientation.quickCaptureShortcut.contains("Space"))
        #expect(WorkspaceOrientation.voiceCaptureShortcut.contains("Record"))
        #expect(WorkspaceOrientation.emptyCaptureGuidance.contains("Command-Shift-Space"))
    }
}
