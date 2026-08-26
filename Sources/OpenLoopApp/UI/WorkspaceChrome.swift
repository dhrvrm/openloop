import ADHDCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceTopBar: View {
    @ObservedObject var model: AppModel
    let destination: WorkspaceDestination
    @Binding var sidebarVisible: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button {
                sidebarVisible.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(OpenLoopVisualSystem.selectionInactive, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("/", modifiers: .command)
            .help(sidebarVisible ? "Hide sidebar · ⌘/" : "Show sidebar · ⌘/")

            VStack(alignment: .leading, spacing: 1) {
                Text(destination.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(destinationDetail)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(OpenLoopVisualSystem.muted)
            }

            Spacer(minLength: 16)

            if let feedback = model.shortcutFeedback {
                ShortcutFeedbackPill(feedback: feedback)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 16)

            ListeningTopBarControl(model: model)

            Menu {
                Section("Listen from") {
                    ForEach(AudioCaptureSource.allCases, id: \.self) { source in
                        Button {
                            model.setAudioCaptureSource(source)
                        } label: {
                            Label(
                                source.title,
                                systemImage: model.audioCaptureSource == source
                                    ? "checkmark"
                                    : source.systemImage
                            )
                        }
                        .disabled(model.meetingJob.isActive)
                    }
                }
                Divider()
                Button {
                    model.setKeepListeningEnabled(!model.keepListeningEnabled)
                } label: {
                    Label(
                        "Keep listening until I stop",
                        systemImage: model.keepListeningEnabled ? "checkmark" : "ear"
                    )
                }
                .disabled(model.meetingJob.isActive && !model.keepListeningEnabled)
                Divider()
                Menu("Appearance") {
                    ForEach(OpenLoopAppearanceMode.allCases, id: \.self) { mode in
                        Button {
                            model.setAppearanceMode(mode)
                        } label: {
                            Label(
                                mode.displayName,
                                systemImage: model.appearanceMode == mode ? "checkmark" : appearanceIcon(for: mode)
                            )
                        }
                    }
                }
                Button {
                    model.setAdvancedModeEnabled(!model.isAdvancedModeEnabled)
                } label: {
                    Label(
                        "Advanced views",
                        systemImage: model.isAdvancedModeEnabled ? "checkmark" : "slider.horizontal.3"
                    )
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(OpenLoopVisualSystem.selectionInactive, in: RoundedRectangle(cornerRadius: 9))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(OpenLoopVisualSystem.canvas.opacity(0.96))
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: model.shortcutFeedback)
    }

    private func appearanceIcon(for mode: OpenLoopAppearanceMode) -> String {
        switch mode {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    private var destinationDetail: String {
        switch destination.id {
        case .now: "What needs your attention"
        case .transcripts: "Recordings and transcripts"
        case .act: "Work you chose to do"
        case .ask: "Search your private memory"
        case .upcoming: "Work with a date"
        case .someday: "Ideas without a deadline"
        case .inbox: "Notes that need one decision"
        case .later: "Useful, not urgent"
        case .return: "Continue where you stopped"
        case .context: "People, projects, and decisions"
        case .emerging: "Repeated topics and questions"
        }
    }
}

private struct ListeningTopBarControl: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button {
            model.showShortcutFeedback(ShortcutFeedback(
                kind: .recording,
                title: isRecording ? "Finishing voice note" : "Listening started",
                shortcut: "⌃⌥R"
            ))
            model.toggleVoiceCapture()
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(isRecording ? OpenLoopVisualSystem.recording : OpenLoopVisualSystem.muted.opacity(0.55))
                    .frame(width: 7, height: 7)
                Image(systemName: model.meetingJob.captureSource.systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(isRecording ? OpenLoopVisualSystem.recording : .primary)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                isRecording
                    ? OpenLoopVisualSystem.recording.opacity(0.11)
                    : OpenLoopVisualSystem.selectionInactive,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        isRecording ? OpenLoopVisualSystem.recording.opacity(0.35) : OpenLoopVisualSystem.hairline,
                        lineWidth: 0.75
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isSystemDictationActive || (model.meetingJob.isActive && !isRecording))
        .help(isRecording ? "Stop and transcribe · ⌃⌥R" : "Start a voice note · ⌃⌥R")
    }

    private var isRecording: Bool {
        model.meetingJob.stage == .recording && !model.isSystemDictationActive
    }

    private var title: String {
        if isRecording { return "Listening · \(model.meetingJob.captureSource.shortTitle)" }
        if model.meetingJob.isActive { return "Transcribing…" }
        return "Start listening · \(model.audioCaptureSource.shortTitle)"
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

                TextField("Write something to remember…", text: $text)
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
                    .help("Save note · Return")
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
                .help("Record a voice note and save its transcript · ⌃⌥R")

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
                    Label(
                        model.isSystemDictationActive ? "Stop typing" : "Type by voice",
                        systemImage: model.isSystemDictationActive ? "stop.fill" : "waveform"
                    )
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(model.isSystemDictationActive
                            ? OpenLoopVisualSystem.recording
                            : OpenLoopVisualSystem.accent)
                        .padding(.horizontal, 9)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(dictationDisabled)
                .help("Dictate into the active app · ⌃⌥Space")

                Menu {
                    Button("Transcribe a file…", systemImage: "waveform.badge.plus") {
                        presentMeetingImporter()
                    }
                    .disabled(model.meetingJob.isActive)
                    Divider()
                    Picker("Writing style", selection: Binding(
                        get: { model.voiceMode },
                        set: { model.setVoiceMode($0) }
                    )) {
                        ForEach(VoiceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .help("Transcribe a file or change the writing style")
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 54)

            Text("Voice note saves here · Type by voice writes in the active app")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(OpenLoopVisualSystem.tertiaryText)
                .padding(.leading, 48)
                .padding(.bottom, 10)
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
        if model.meetingJob.stage == .recording {
            return "LIVE · \(model.meetingJob.captureSource.shortTitle.uppercased()) · LOCAL"
        }
        if model.meetingJob.isActive { return "\(Int(model.meetingJob.fraction * 100))%" }
        return model.meetingJob.stage == .ready ? "READY" : "LOCAL"
    }

    private var recordButtonTitle: String {
        model.meetingJob.stage == .recording && !model.isSystemDictationActive ? "Stop" : "Voice note"
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
        .accessibilityLabel("Audio input level")
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
