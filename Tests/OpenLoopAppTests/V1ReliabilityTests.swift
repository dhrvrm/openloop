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
            "Now", "Upcoming", "Someday", "Inbox", "Later", "Return",
        ])
        #expect(WorkspaceOrientation.sections[1].destinations.map(\.title) == [
            "Transcripts", "Context", "Emerging", "Ask", "Act",
        ])
        #expect(Set(WorkspaceOrientation.destinations.map(\.id)).count == 11)
        #expect(Set(WorkspaceOrientation.destinations.map(\.icon)).count == 11)
        #expect(WorkspaceOrientation.destination(atLegacyTab: 0) == .now)
        #expect(WorkspaceOrientation.destination(atLegacyTab: 3) == .ask)
        #expect(WorkspaceOrientation.destination(atLegacyTab: 99) == .now)
        #expect(WorkspaceOrientation.quickCaptureShortcut.contains("Space"))
        #expect(WorkspaceOrientation.voiceCaptureShortcut.contains("⌃⌥Space"))
        #expect(WorkspaceOrientation.emptyCaptureGuidance.contains("Command-Shift-Space"))
    }

    @Test func globalVoiceHUDUsesOneObservableSessionState() {
        #expect(VoiceHUDPresentation.phase(
            isSystemDictationActive: true,
            meetingStage: .recording,
            isDelivering: false,
            deliveryState: nil,
            hasNotice: false
        ) == .recording)
        #expect(VoiceHUDPresentation.phase(
            isSystemDictationActive: false,
            meetingStage: .ready,
            isDelivering: true,
            deliveryState: nil,
            hasNotice: false
        ) == .processing)
        #expect(VoiceHUDPresentation.phase(
            isSystemDictationActive: false,
            meetingStage: .ready,
            isDelivering: false,
            deliveryState: .inserted,
            hasNotice: false
        ) == .success)
        #expect(VoiceHUDPresentation.phase(
            isSystemDictationActive: false,
            meetingStage: .failed,
            isDelivering: false,
            deliveryState: nil,
            hasNotice: true
        ) == .failure)
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
        #expect(OpenLoopVisualSystem.space1 == 4)
        #expect(OpenLoopVisualSystem.space2 == 8)
        #expect(OpenLoopVisualSystem.space3 == 12)
        #expect(OpenLoopVisualSystem.space4 == 20)
        #expect(OpenLoopVisualSystem.space5 == 32)
        #expect(OpenLoopVisualSystem.sidebarWidth == 252)
        #expect(OpenLoopVisualSystem.contentMaximumWidth == 760)
        #expect(OpenLoopVisualSystem.checkboxSize == 18)
        #expect(OpenLoopVisualSystem.checkboxHitSize == 28)
        #expect(OpenLoopVisualSystem.taskRowMinimumHeight == 44)
        #expect(OpenLoopVisualSystem.sidebarSelectionRadius == 6)
        #expect(OpenLoopVisualSystem.inputRadius == 8)
        #expect(OpenLoopVisualSystem.editorRadius == 10)
        #expect(OpenLoopVisualSystem.panelRadius == 10)
        #expect(OpenLoopVisualSystem.contentTopPadding == 52)
        #expect(OpenLoopVisualSystem.contentBottomPadding == 48)
        #expect(OpenLoopVisualSystem.contentHorizontalPadding == 40)
        #expect(OpenLoopVisualSystem.inspectorTopPadding == 32)
        #expect(OpenLoopVisualSystem.inspectorBottomPadding == 40)
    }
}
