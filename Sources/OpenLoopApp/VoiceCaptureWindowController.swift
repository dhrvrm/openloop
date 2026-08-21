import AppKit
import Combine
import SwiftUI

private struct VoiceCaptureView: View {
    @ObservedObject var controller: VoiceTranscriptionController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Circle()
                    .fill(controller.state == .recording ? Color.red : Color.secondary.opacity(0.35))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                Spacer()
                if controller.state == .recording, let startedAt = controller.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsed(from: startedAt, to: context.date))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(controller.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)

            if controller.state == .recording {
                HStack(alignment: .center, spacing: 5) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(activityColor(for: index))
                            .frame(width: 5, height: CGFloat(8 + index * 3))
                    }
                    Text(controller.hasDetectedSpeech ? "Voice detected" : "Listening")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Microphone activity")
                .accessibilityValue(controller.hasDetectedSpeech ? "Voice detected" : "Listening")
            }

            TextEditor(text: Binding(
                get: { controller.transcript },
                set: { controller.editTranscript($0) }
            ))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .frame(minHeight: 110)
                .disabled(controller.state == .requestingPermission || controller.state == .saving)
                .accessibilityLabel("Live transcript")

            Text("Edits improve names and technical words on this Mac")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack {
                Text("⌃⌥Space to \(controller.state == .recording ? "stop and save" : "start")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { controller.cancel() }
                primaryButton
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    @ViewBuilder private var primaryButton: some View {
        switch controller.state {
        case .recording:
            Button("Stop & Save") { Task { await controller.toggle() } }
                .buttonStyle(.borderedProminent)
        case .failed:
            Button(controller.transcript.isEmpty ? "Try Again" : "Retry Save") {
                Task { await controller.toggle() }
            }
            .buttonStyle(.borderedProminent)
        case .requestingPermission:
            Button("Checking…") {}
                .buttonStyle(.borderedProminent)
                .disabled(true)
        case .saving:
            Button("Saving…") {}
                .buttonStyle(.borderedProminent)
                .disabled(true)
        case .idle:
            EmptyView()
        }
    }

    private var title: String {
        switch controller.state {
        case .idle: "Voice capture"
        case .requestingPermission: "Preparing voice capture"
        case .recording: "Recording"
        case .saving: "Saving transcript"
        case .failed: "Voice capture needs attention"
        }
    }

    private func elapsed(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func activityColor(for index: Int) -> Color {
        let threshold = Double(index + 1) / 5
        return controller.audioLevel >= threshold
            ? .accentColor
            : Color.secondary.opacity(0.2)
    }
}

@MainActor
final class VoiceCaptureWindowController {
    private let controller: VoiceTranscriptionController
    private let window: NSPanel
    private var stateObservation: AnyCancellable?

    init(controller: VoiceTranscriptionController) {
        self.controller = controller
        window = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = "Voice Capture"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = NSHostingController(
            rootView: VoiceCaptureView(controller: controller)
        )
        stateObservation = controller.$state.sink { [weak self] state in
            guard let self else { return }
            if state == .idle {
                window.orderOut(nil)
            } else {
                showWindow()
            }
        }
    }

    func toggle() {
        if controller.state == .idle || controller.state == .failed {
            showWindow()
        }
        Task { await controller.toggle() }
    }

    private func showWindow() {
        window.center()
        window.orderFrontRegardless()
    }
}
