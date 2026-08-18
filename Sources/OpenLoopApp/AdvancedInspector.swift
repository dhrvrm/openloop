import ADHDCore
import SwiftUI

struct AdvancedInspector: View {
    @ObservedObject var model: AppModel
    let selectedDestination: WorkspaceDestination

    private var nodes: [MeetingPipelineNode] {
        MeetingPipelineNode.project(stage: model.meetingJob.stage)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                inspectorHeader
                liveStatus
                pipeline
                engineFacts
                recentEvents
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
        .background(.ultraThinMaterial)
        .accessibilityLabel("Advanced system inspector")
    }

    private var inspectorHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(OpenLoopVisualSystem.accentSoft)
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(OpenLoopVisualSystem.accent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Advanced")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("LIVE SYSTEM")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var liveStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current surface")
                    .foregroundStyle(.secondary)
                Spacer()
                Label(selectedDestination.title, systemImage: selectedDestination.icon)
                    .fontWeight(.medium)
            }
            HStack {
                Text("Meeting engine")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(jobStatus)
                    .fontWeight(.medium)
            }
            if model.meetingJob.isActive {
                ProgressView(value: model.meetingJob.fraction)
                    .tint(OpenLoopVisualSystem.accent)
                Text(model.meetingJob.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
        .padding(13)
        .openLoopPanel(emphasized: model.meetingJob.isActive)
    }

    private var pipeline: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionLabel("TRANSCRIPTION PIPELINE", icon: "point.3.connected.trianglepath.dotted")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    PipelineNodeRow(node: node)
                    if index < nodes.count - 1 {
                        Rectangle()
                            .fill(connectorColor(after: node))
                            .frame(width: 1, height: 11)
                            .padding(.leading, 7)
                    }
                }
            }
        }
    }

    private var engineFacts: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionLabel("LOCAL ENGINE", icon: "cpu")
            VStack(spacing: 0) {
                InspectorFact(
                    label: "Transcription",
                    value: model.meetingEngineDiagnostics.transcriptionModel
                )
                Divider()
                InspectorFact(
                    label: "Model state",
                    value: model.meetingEngineDiagnostics.transcriptionModelState.title
                )
                Divider()
                InspectorFact(
                    label: "Speakers",
                    value: model.meetingEngineDiagnostics.diarizationModel
                )
                Divider()
                InspectorLanguageControl(model: model)
                Divider()
                InspectorFact(
                    label: "Compute",
                    value: model.meetingEngineDiagnostics.processingLocation
                )
                Divider()
                InspectorFact(label: "Microphone", value: availability(model.capabilitySummary.microphone))
            }
            .padding(.horizontal, 12)
            .openLoopPanel()

            VStack(alignment: .leading, spacing: 7) {
                Label("Encrypted vault", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OpenLoopVisualSystem.accent)
                Text("\(model.meetingTranscripts.count) meeting transcript\(model.meetingTranscripts.count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: model.privacySummary.encryptedBytes, countStyle: .file)) encrypted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.meetingEngineDiagnostics.modelCacheLocation)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .padding(12)
            .openLoopPanel()
        }
    }

    @ViewBuilder private var recentEvents: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionLabel("RECENT ACTIVITY", icon: "clock.arrow.circlepath")
            if model.meetingPipelineEvents.isEmpty {
                Text("Pipeline events appear here while an import or recording is processed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .openLoopPanel()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(model.meetingPipelineEvents.suffix(10).reversed())) { event in
                        HStack(alignment: .top, spacing: 9) {
                            Text(event.occurredAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 46, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stageName(event.stage))
                                    .font(.caption.weight(.semibold))
                                Text(event.message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(12)
                .openLoopPanel()
            }
        }
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var jobStatus: String {
        guard model.meetingJob.stage != nil else { return "Idle" }
        if model.meetingJob.isActive { return "Working · \(Int(model.meetingJob.fraction * 100))%" }
        return model.meetingJob.message
    }

    private func connectorColor(after node: MeetingPipelineNode) -> Color {
        node.state == .complete ? OpenLoopVisualSystem.accent.opacity(0.65) : OpenLoopVisualSystem.hairline
    }

    private func availability(_ value: CapabilityAvailability) -> String {
        switch value {
        case .ready: "Ready"
        case .askWhenUsed: "Asks when used"
        case .unavailable: "Off in Settings"
        case .checking: "Checking"
        }
    }

    private func stageName(_ stage: MeetingTranscriptionStage) -> String {
        switch stage {
        case .requestingMicrophone: "Microphone"
        case .recording: "Recording"
        case .waitingForModel: "Model"
        case .downloadingModel: "Download"
        case .preparingAudio: "Audio staging"
        case .transcribing: "Whisper"
        case .diarizing: "Speakers"
        case .saving: "Vault"
        case .ready: "Recall"
        case .failed: "Attention"
        case .cancelled: "Cancelled"
        }
    }
}

private struct PipelineNodeRow: View {
    let node: MeetingPipelineNode

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(node.state == .idle ? 0.10 : 0.16))
                if node.state == .complete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(color)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: node.state == .active ? 7 : 5, height: node.state == .active ? 7 : 5)
                }
            }
            .frame(width: 15, height: 15)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(node.kind.title)
                        .font(.caption.weight(node.state == .active ? .semibold : .regular))
                    Spacer()
                    if node.state == .active {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(color)
                    }
                }
                Text(node.kind.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var color: Color {
        switch node.state {
        case .idle: .secondary
        case .active, .complete: OpenLoopVisualSystem.accent
        case .attention: .orange
        }
    }
}

private struct InspectorFact: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
        .padding(.vertical, 9)
    }
}

private struct InspectorLanguageControl: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Language detection")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Picker(
                    "Language detection",
                    selection: Binding(
                        get: { model.meetingLanguagePreference },
                        set: { model.setMeetingLanguagePreference($0) }
                    )
                ) {
                    ForEach(MeetingLanguagePreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 142)
                .disabled(model.meetingJob.isActive)
            }
            Text(model.meetingLanguagePreference == .automatic
                ? "Whisper detects the spoken language from each recording."
                : "Temporary override for this app session.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .padding(.vertical, 8)
    }
}
