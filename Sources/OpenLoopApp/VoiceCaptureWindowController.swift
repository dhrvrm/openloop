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

            TextEditor(text: $controller.transcript)
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

            HStack {
                Text("⌘⇧R to \(controller.state == .recording ? "stop and save" : "start")")
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
            styleMask: [.titled, .utilityWindow],
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
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
