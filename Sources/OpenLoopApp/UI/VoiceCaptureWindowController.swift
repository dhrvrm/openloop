import ADHDCore
import AppKit
import Combine
import SwiftUI

enum VoiceHUDPhase: Equatable {
    case hidden
    case recording
    case processing
    case confirmation
    case success
    case failure
}

enum VoiceHUDPresentation {
    static func phase(
        isSystemDictationActive: Bool,
        meetingStage: MeetingTranscriptionStage?,
        isDelivering: Bool,
        deliveryState: VoiceDictationDeliveryState?,
        hasNotice: Bool
    ) -> VoiceHUDPhase {
        if isSystemDictationActive, meetingStage == .recording { return .recording }
        if isDelivering || (isSystemDictationActive && meetingStage != .failed) {
            return .processing
        }
        switch deliveryState {
        case .awaitingConfirmation: return .confirmation
        case .inserted: return .success
        case .failed: return .failure
        case nil: return hasNotice ? .failure : .hidden
        }
    }
}

private struct GlobalVoiceHUD: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Circle()
                    .fill(phase == .recording ? OpenLoopVisualSystem.recording : statusTint)
                    .frame(width: 9, height: 9)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if phase == .recording, let startedAt = model.meetingJob.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsed(from: startedAt, to: context.date))
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(decibelText)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if phase == .recording {
                meter
                transcript
            } else {
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Text("⌃⌥Space")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                Spacer()
                if phase == .recording {
                    Button("Cancel") { model.cancelVoiceCapture() }
                    Button("Stop & insert") { model.toggleSystemDictation() }
                        .buttonStyle(OpenLoopAccessoryButtonStyle(tint: OpenLoopVisualSystem.recording))
                } else if phase == .confirmation {
                    Button("Cancel") { model.discardPendingVoiceCommand() }
                    Button("Confirm") { model.confirmPendingVoiceCommand() }
                        .buttonStyle(OpenLoopAccessoryButtonStyle())
                } else if phase == .failure {
                    Button("Dismiss") { model.dismissDictationStatus() }
                }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 430)
        .background(OpenLoopVisualSystem.raised)
    }

    private var phase: VoiceHUDPhase {
        VoiceHUDPresentation.phase(
            isSystemDictationActive: model.isSystemDictationActive,
            meetingStage: model.meetingJob.stage,
            isDelivering: model.isDeliveringDictation,
            deliveryState: model.lastDictationDelivery?.state,
            hasNotice: model.dictationActionNotice != nil || model.commandError != nil
        )
    }

    private var title: String {
        switch phase {
        case .hidden: "Dictation"
        case .recording: "Listening"
        case .processing: "Preparing your words"
        case .confirmation: "Confirm voice command"
        case .success: "Inserted"
        case .failure: "Dictation needs attention"
        }
    }

    private var statusText: String {
        if let delivery = model.lastDictationDelivery { return delivery.statusMessage }
        return model.commandError
            ?? model.dictationActionNotice
            ?? model.dictationProcessingMessage
            ?? model.meetingJob.message
    }

    private var statusTint: Color {
        phase == .failure ? .orange : OpenLoopVisualSystem.accent
    }

    private var transcript: some View {
        let snapshot = model.streamingVoiceSession
        return VStack(alignment: .leading, spacing: 5) {
            if let stable = snapshot?.transcript.stableText, !stable.isEmpty {
                Text(stable)
                    .foregroundStyle(.primary)
            }
            if let partial = snapshot?.transcript.unstableText, !partial.isEmpty {
                Text(partial)
                    .foregroundStyle(.secondary)
                Text("Still listening")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if snapshot?.transcript.visibleText.isEmpty != false {
                Text("Speak naturally in Hindi, English, or both.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 14))
        .lineLimit(4)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
        .textSelection(.enabled)
        .accessibilityLabel("Live dictation transcript")
    }

    private var meter: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<18, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index <= activeBarCount
                        ? OpenLoopVisualSystem.recording
                        : Color.secondary.opacity(0.16))
                    .frame(width: 4, height: CGFloat(6 + (index * 7 % 20)))
            }
        }
        .frame(height: 28)
        .animation(.easeOut(duration: 0.1), value: model.recordingDecibels)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone level")
        .accessibilityValue(decibelText)
    }

    private var activeBarCount: Int {
        guard let decibels = model.recordingDecibels else { return 0 }
        return Int((min(0, max(-60, decibels)) + 60) / 60 * 17)
    }

    private var decibelText: String {
        model.recordingDecibels.map { String(format: "%.0f dB", $0) } ?? "— dB"
    }

    private func elapsed(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

@MainActor
final class VoiceCaptureWindowController {
    private let model: AppModel
    private let window: NSPanel
    private var modelObservation: AnyCancellable?
    private var successDismissal: Task<Void, Never>?
    private var suppressedSuccessToken: String?

    init(model: AppModel) {
        self.model = model
        window = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentViewController = NSHostingController(rootView: GlobalVoiceHUD(model: model))
        modelObservation = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                await Task.yield()
                self?.refreshVisibility()
            }
        }
    }

    private func refreshVisibility() {
        let phase = VoiceHUDPresentation.phase(
            isSystemDictationActive: model.isSystemDictationActive,
            meetingStage: model.meetingJob.stage,
            isDelivering: model.isDeliveringDictation,
            deliveryState: model.lastDictationDelivery?.state,
            hasNotice: model.dictationActionNotice != nil || model.commandError != nil
        )
        if phase == .hidden {
            successDismissal?.cancel()
            window.orderOut(nil)
            return
        }
        if phase == .recording || phase == .processing { suppressedSuccessToken = nil }
        if phase == .success {
            let token = model.lastDictationDelivery.map {
                "\($0.state.rawValue)|\($0.processedText)"
            }
            guard token != suppressedSuccessToken else { return }
            successDismissal?.cancel()
            successDismissal = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.2))
                guard !Task.isCancelled, let self else { return }
                suppressedSuccessToken = token
                window.orderOut(nil)
            }
        }
        showWithoutActivating()
    }

    private func showWithoutActivating() {
        if let screen = NSScreen.main {
            let size = window.frame.size
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - size.height - 24
            ))
        } else {
            window.center()
        }
        window.orderFrontRegardless()
    }
}
