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
        #expect(WorkspaceOrientation.sections.map(\.title) == ["Focus", "Intelligence"])
        #expect(WorkspaceOrientation.sections[0].destinations.map(\.title) == [
            "Now", "Inbox", "Later", "Return",
        ])
        #expect(WorkspaceOrientation.sections[1].destinations.map(\.title) == [
            "Context", "Emerging", "Ask", "Act",
        ])
        #expect(Set(WorkspaceOrientation.destinations.map(\.id)).count == 8)
        #expect(Set(WorkspaceOrientation.destinations.map(\.icon)).count == 8)
        #expect(WorkspaceOrientation.destination(atLegacyTab: 0) == .now)
        #expect(WorkspaceOrientation.destination(atLegacyTab: 3) == .ask)
        #expect(WorkspaceOrientation.destination(atLegacyTab: 99) == .now)
        #expect(WorkspaceOrientation.quickCaptureShortcut.contains("Space"))
        #expect(WorkspaceOrientation.voiceCaptureShortcut.contains("⌃⌥Space"))
        #expect(WorkspaceOrientation.emptyCaptureGuidance.contains("Command-Shift-Space"))
    }

    @Test func visibleRecordControlNamesEveryVoiceState() {
        #expect(VoiceRecordButtonPresentation.title(for: VoiceCapturePresentation()) == "Record")
        #expect(VoiceRecordButtonPresentation.title(for: VoiceCapturePresentation(
            state: .recording
        )) == "Stop & save")
        #expect(VoiceRecordButtonPresentation.title(for: VoiceCapturePresentation(
            state: .failed,
            transcript: "retained words"
        )) == "Retry save")
        #expect(VoiceRecordButtonPresentation.systemImage(for: .recording) == "stop.fill")
        #expect(VoiceRecordButtonPresentation.isDisabled(.requestingPermission))
        #expect(VoiceRecordButtonPresentation.isDisabled(.saving))
        #expect(VoiceRecordButtonPresentation.isDisabled(.idle) == false)
    }

    @Test func nativeWorkspaceGeometryKeepsOneCompactVisualRhythm() {
        #expect(OpenLoopVisualSystem.sidebarWidth == 238)
        #expect(OpenLoopVisualSystem.contentMaximumWidth == 720)
        #expect(OpenLoopVisualSystem.checkboxSize == 18)
        #expect(OpenLoopVisualSystem.checkboxHitSize == 28)
        #expect(OpenLoopVisualSystem.taskRowMinimumHeight == 47)
        #expect(OpenLoopVisualSystem.sidebarSelectionRadius == 7)
        #expect(OpenLoopVisualSystem.inputRadius == 9)
        #expect(OpenLoopVisualSystem.editorRadius == 11)
        #expect(OpenLoopVisualSystem.panelRadius == 11)
    }
}
