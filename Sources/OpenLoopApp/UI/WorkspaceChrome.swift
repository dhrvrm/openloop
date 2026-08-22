import ADHDCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceTopBar: View {
    @ObservedObject var model: AppModel
    let destination: WorkspaceDestination
    @Binding var sidebarVisible: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                sidebarVisible.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("/", modifiers: .command)
            .help(sidebarVisible ? "Hide sidebar · ⌘/" : "Show sidebar · ⌘/")

            Text(destination.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(OpenLoopVisualSystem.muted)

            Spacer(minLength: 16)

            if let feedback = model.shortcutFeedback {
                ShortcutFeedbackPill(feedback: feedback)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 16)

            Menu {
                ForEach(OpenLoopAppearanceMode.allCases, id: \.self) { mode in
                    Button {
                        model.setAppearanceMode(mode)
                    } label: {
                        if model.appearanceMode == mode {
                            Label(mode.displayName, systemImage: "checkmark")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                }
            } label: {
                Image(systemName: appearanceIcon)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help("Appearance · \(model.appearanceMode.displayName)")

            Button {
                model.setAdvancedModeEnabled(!model.isAdvancedModeEnabled)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(model.isAdvancedModeEnabled
                        ? OpenLoopVisualSystem.accent
                        : OpenLoopVisualSystem.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help("Advanced system details · ⌥⌘I")
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(OpenLoopVisualSystem.canvas.opacity(0.96))
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: model.shortcutFeedback)
    }

    private var appearanceIcon: String {
        switch model.appearanceMode {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

private struct ShortcutFeedbackPill: View {
    let feedback: ShortcutFeedback

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(feedback.title)
                .font(.system(size: 12.5, weight: .medium))
            Text(feedback.shortcut)
                .font(.system(size: 11, weight: .medium).monospaced())
                .foregroundStyle(OpenLoopVisualSystem.muted)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(
            OpenLoopVisualSystem.selectionInactive,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(OpenLoopVisualSystem.hairline, lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch feedback.kind {
        case .recording: OpenLoopVisualSystem.recording
        case .warning: .orange
        default: OpenLoopVisualSystem.accent
        }
    }

    private var icon: String {
        switch feedback.kind {
        case .capture: "plus"
        case .recording: "record.circle.fill"
        case .dictation: "waveform"
        case .search: "magnifyingglass"
        case .warning: "exclamationmark.triangle"
        }
    }
}

struct OpenLoopCaptureDock: View {
    @ObservedObject var model: AppModel
    @Binding var text: String
    let submit: () async -> Void
    @FocusState private var textFocused: Bool
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.meetingJob.stage != nil || model.isDeliveringDictation {
                captureStatus
                Divider().padding(.horizontal, 14)
            }

            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OpenLoopVisualSystem.accent)
                    .frame(width: 28, height: 28)

                TextField("Capture a thought…", text: $text)
                    .textFieldStyle(.plain)
                    .font(OpenLoopVisualSystem.rowTitle)
                    .focused($textFocused)
                    .onSubmit { Task { await submit() } }

                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        Task { await submit() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(OpenLoopVisualSystem.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSaving)
                    .help("Save thought · Return")
                }

                Rectangle()
                    .fill(OpenLoopVisualSystem.separator)
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 4)

                Button {
                    model.showShortcutFeedback(ShortcutFeedback(
                        kind: .recording,
                        title: model.meetingJob.stage == .recording
                            ? "Finishing recording"
                            : "Recording started",
                        shortcut: "⌃⌥R"
                    ))
                    model.toggleVoiceCapture()
                } label: {
                    Label(recordButtonTitle, systemImage: recordButtonIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(OpenLoopVisualSystem.recording, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(recordDisabled)
                .help("Record and transcribe · ⌃⌥R")

                Button {
                    model.showShortcutFeedback(ShortcutFeedback(
                        kind: .dictation,
                        title: model.isSystemDictationActive
                            ? "Finishing dictation"
                            : "Dictation started",
                        shortcut: "⌃⌥Space"
                    ))
                    model.toggleSystemDictation()
                } label: {
                    Image(systemName: model.isSystemDictationActive ? "stop.fill" : "waveform")
                        .foregroundStyle(model.isSystemDictationActive
                            ? OpenLoopVisualSystem.recording
                            : OpenLoopVisualSystem.accent)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(dictationDisabled)
                .help("Dictate into the active app · ⌃⌥Space")

                Menu {
                    Button("Import audio…", systemImage: "waveform.badge.plus") {
                        presentMeetingImporter()
                    }
                    .disabled(model.meetingJob.isActive)
                    Divider()
                    Picker("Voice style", selection: Binding(
                        get: { model.voiceMode },
                        set: { model.setVoiceMode($0) }
                    )) {
                        ForEach(VoiceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .help("More capture options")
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 56)
        }
        .frame(maxWidth: 760)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(OpenLoopVisualSystem.raised.opacity(0.86), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(textFocused ? OpenLoopVisualSystem.focusRing : OpenLoopVisualSystem.hairline, lineWidth: textFocused ? 1.5 : 0.75)
        }
        .shadow(color: Color.black.opacity(hovered ? 0.16 : 0.11), radius: hovered ? 26 : 18, y: 8)
        .scaleEffect(hovered ? 1.003 : 1)
        .onHover { value in
            hovered = value
        }
        .animation(.easeOut(duration: 0.18), value: hovered)
    }

    @ViewBuilder private var captureStatus: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Circle()
                    .fill(model.meetingJob.stage == .recording
                        ? OpenLoopVisualSystem.recording
                        : OpenLoopVisualSystem.accent)
                    .frame(width: 8, height: 8)
                Text(model.meetingJob.sourceName ?? statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(statusDetail)
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(OpenLoopVisualSystem.muted)
            }

            if model.meetingJob.stage == .recording {
                CaptureWaveform(decibels: model.recordingDecibels)
                if let text = model.streamingVoiceSession?.transcript.visibleText,
                   !text.isEmpty {
                    Text(text)
                        .font(OpenLoopVisualSystem.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            } else if model.meetingJob.isActive {
                ProgressView(value: model.meetingJob.fraction)
                    .tint(OpenLoopVisualSystem.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusTitle: String {
        model.isDeliveringDictation ? "Preparing text" : model.meetingJob.message
    }

    private var statusDetail: String {
        if model.meetingJob.stage == .recording { return "LIVE · LOCAL" }
        if model.meetingJob.isActive { return "\(Int(model.meetingJob.fraction * 100))%" }
        return model.meetingJob.stage == .ready ? "READY" : "LOCAL"
    }

    private var recordButtonTitle: String {
        model.meetingJob.stage == .recording && !model.isSystemDictationActive ? "Stop" : "Record"
    }

    private var recordButtonIcon: String {
        model.meetingJob.stage == .recording && !model.isSystemDictationActive
            ? "stop.fill"
            : "record.circle.fill"
    }

    private var recordDisabled: Bool {
        model.isSystemDictationActive
            || (model.meetingJob.isActive && model.meetingJob.stage != .recording)
    }

    private var dictationDisabled: Bool {
        model.meetingJob.isActive
            && !(model.isSystemDictationActive && model.meetingJob.stage == .recording)
    }

    private func presentMeetingImporter() {
        let panel = NSOpenPanel()
        panel.title = "Choose a recording"
        panel.prompt = "Transcribe locally"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mpeg4Movie]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.importMeetingAudio(url)
        }
    }
}

private struct CaptureWaveform: View {
    let decibels: Float?
    private let barCount = 36

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(index < activeBars
                        ? OpenLoopVisualSystem.recording
                        : OpenLoopVisualSystem.recording.opacity(0.13))
                    .frame(width: 3, height: barHeight(index))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
        .animation(.easeOut(duration: 0.09), value: decibels)
        .accessibilityLabel("Microphone level")
        .accessibilityValue(decibels.map { "\(Int($0.rounded())) decibels" } ?? "Waiting")
    }

    private var level: CGFloat {
        guard let decibels else { return 0 }
        return CGFloat(min(1, max(0, (decibels + 60) / 60)))
    }

    private var activeBars: Int { Int((level * CGFloat(barCount)).rounded()) }

    private func barHeight(_ index: Int) -> CGFloat {
        let profile = CGFloat(0.34 + 0.66 * abs(sin(Double(index) * 1.19)))
        return max(4, (7 + level * 25) * profile)
    }
}
