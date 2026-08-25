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

enum VoiceHUDTone: Equatable, Sendable {
    case neutral
    case recording
    case success
    case warning
}

struct VoiceHUDContent: Equatable, Sendable {
    let title: String
    let detail: String
    let tone: VoiceHUDTone
    let showsMeter: Bool
    let showsTranscript: Bool
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

    static func content(
        phase: VoiceHUDPhase,
        statusText: String,
        hasLiveTranscript: Bool
    ) -> VoiceHUDContent {
        switch phase {
        case .hidden:
            VoiceHUDContent(
                title: "Dictation", detail: statusText, tone: .neutral,
                showsMeter: false, showsTranscript: false
            )
        case .recording:
            VoiceHUDContent(
                title: "Listening",
                detail: statusText.isEmpty
                    ? "Speak naturally in Hindi, English, or both."
                    : statusText,
                tone: .recording,
                showsMeter: true,
                showsTranscript: true
            )
        case .processing:
            VoiceHUDContent(
                title: "Improving accuracy",
                detail: statusText.isEmpty
                    ? "Checking the complete recording locally."
                    : statusText,
                tone: .neutral,
                showsMeter: false,
                showsTranscript: hasLiveTranscript
            )
        case .confirmation:
            VoiceHUDContent(
                title: "Confirm voice command", detail: statusText, tone: .warning,
                showsMeter: false, showsTranscript: false
            )
        case .success:
            VoiceHUDContent(
                title: "Inserted", detail: statusText, tone: .success,
                showsMeter: false, showsTranscript: false
            )
        case .failure:
            VoiceHUDContent(
                title: "Couldn’t insert", detail: statusText, tone: .warning,
                showsMeter: false, showsTranscript: false
            )
        }
    }

    static func panelSize(for phase: VoiceHUDPhase) -> NSSize {
        switch phase {
        case .hidden, .success: NSSize(width: 264, height: 68)
        case .processing: NSSize(width: 340, height: 108)
        case .recording: NSSize(width: 384, height: 194)
        case .confirmation, .failure: NSSize(width: 384, height: 150)
        }
    }
}

private struct GlobalVoiceHUD: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                statusMark
                Text(content.title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                Spacer()
                if phase == .recording, let startedAt = model.meetingJob.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsed(from: startedAt, to: context.date))
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                if phase == .recording {
                    Text(decibelText)
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if content.showsMeter {
                meter
            }
            if content.showsTranscript {
                transcript
            } else if phase == .processing {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text(content.detail)
                        .lineLimit(2)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            } else {
                Text(content.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if phase == .recording || phase == .confirmation || phase == .failure {
                HStack(spacing: 10) {
                    Text("⌃⌥Space")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if phase == .recording {
                        Button("Cancel") { model.cancelVoiceCapture() }
                        Button("Stop") { model.toggleSystemDictation() }
                            .buttonStyle(OpenLoopAccessoryButtonStyle(
                                tint: OpenLoopVisualSystem.recording
                            ))
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
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, phase == .success ? 14 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.75)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: phase)
    }

    @ViewBuilder
    private var statusMark: some View {
        if phase == .processing {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 10, height: 10)
        } else {
            Circle()
                .fill(statusTint)
                .frame(width: 9, height: 9)
                .shadow(
                    color: statusTint.opacity(phase == .recording ? 0.45 : 0),
                    radius: 4
                )
        }
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

    private var content: VoiceHUDContent {
        VoiceHUDPresentation.content(
            phase: phase,
            statusText: statusText,
            hasLiveTranscript: model.streamingVoiceSession?.transcript.visibleText.isEmpty == false
        )
    }

    private var statusText: String {
        if let delivery = model.lastDictationDelivery { return delivery.statusMessage }
        return model.commandError
            ?? model.dictationActionNotice
            ?? model.dictationProcessingMessage
            ?? model.meetingJob.message
    }

    private var statusTint: Color {
        switch content.tone {
        case .neutral: OpenLoopVisualSystem.accent
        case .recording: OpenLoopVisualSystem.recording
        case .success: Color(nsColor: .systemGreen)
        case .warning: Color(nsColor: .systemOrange)
        }
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
            }
            if snapshot?.transcript.visibleText.isEmpty != false {
                Text(content.detail)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13.5, weight: .regular))
        .lineLimit(3)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
        .textSelection(.enabled)
        .accessibilityLabel("Live dictation transcript")
    }

    private var meter: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<21, id: \.self) { index in
                let distance = abs(index - 10)
                let baseHeight = max(5, 24 - distance * 2)
                Capsule(style: .continuous)
                    .fill(index <= activeBarCount
                        ? OpenLoopVisualSystem.recording
                        : Color.secondary.opacity(0.14))
                    .frame(width: 3.5, height: CGFloat(baseHeight))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .animation(.easeOut(duration: 0.1), value: model.recordingDecibels)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone level")
        .accessibilityValue(decibelText)
    }

    private var activeBarCount: Int {
        guard let decibels = model.recordingDecibels else { return 0 }
        return Int((min(0, max(-60, decibels)) + 60) / 60 * 20)
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
            contentRect: NSRect(
                origin: .zero,
                size: VoiceHUDPresentation.panelSize(for: .hidden)
            ),
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
        window.hidesOnDeactivate = false
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
        resize(for: phase)
        showWithoutActivating()
    }

    private func resize(for phase: VoiceHUDPhase) {
        let size = VoiceHUDPresentation.panelSize(for: phase)
        guard window.frame.size != size else { return }
        var frame = window.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        window.setFrame(frame, display: true, animate: window.isVisible)
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
