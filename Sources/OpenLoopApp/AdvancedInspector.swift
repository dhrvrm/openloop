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
                runtimeTrace
                pipeline
                engineFacts
                qualityEvidence
                recentEvents
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
        .background(.ultraThinMaterial)
        .accessibilityLabel("Advanced system inspector")
    }

    private var runtime: AdvancedRuntimeProjection {
        AdvancedRuntimeProjection.project(
            job: model.meetingJob,
            recordingDecibels: model.recordingDecibels,
            transcripts: model.meetingTranscripts,
            diagnostics: model.meetingEngineDiagnostics
        )
    }

    private var runtimeTrace: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionLabel("LIVE DECISION TRACE", icon: "waveform.path.ecg")
            VStack(spacing: 0) {
                InspectorFact(label: "Audio signal", value: liveAudioSignal)
                Divider()
                InspectorFact(label: "VAD", value: liveVADState)
                Divider()
                InspectorFact(label: "Recognizer", value: liveRecognizer)
                Divider()
                InspectorFact(label: "Fusion", value: runtime.fusionStatus)
                Divider()
                InspectorFact(label: "Editor", value: editorRoute)
                Divider()
                InspectorFact(label: "Output", value: outputRoute)
            }
            .padding(.horizontal, 12)
            .openLoopPanel(emphasized: model.meetingJob.isActive)

            if liveUnstableText != "None" {
                VStack(alignment: .leading, spacing: 5) {
                    Text("UNSTABLE / LIVE")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(liveUnstableText)
                        .font(.caption)
                        .lineLimit(5)
                        .textSelection(.enabled)
                }
                .padding(12)
                .openLoopPanel()
            }
            if let stable = model.streamingVoiceSession?.transcript.stableText,
               !stable.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("STABLE / COMMITTED")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(OpenLoopVisualSystem.accent)
                    Text(stable)
                        .font(.caption)
                        .lineLimit(8)
                        .textSelection(.enabled)
                }
                .padding(12)
                .openLoopPanel()
            }
        }
    }

    private var liveAudioSignal: String {
        guard let value = model.streamingVoiceSession?.inputDecibels else {
            return runtime.audioSignal
        }
        return "\(Int(value.rounded())) dB · \(model.streamingVoiceSession?.processedFrameCount ?? 0) frames"
    }

    private var liveVADState: String {
        guard let snapshot = model.streamingVoiceSession else { return runtime.vadState }
        return snapshot.vadState == .speech ? "Speech" : "Silence"
    }

    private var liveRecognizer: String {
        model.streamingVoiceSession?.activeRecognizer ?? runtime.activeRecognizer
    }

    private var editorRoute: String {
        if model.isDeliveringDictation {
            return model.dictationProcessingMessage ?? "Processing locally"
        }
        guard let delivery = model.lastDictationDelivery else { return runtime.editorRoute }
        switch delivery.processingRoute {
        case .direct: return "Raw · deterministic"
        case .deterministicCommand: return "Voice command"
        case .compactLocalEditor: return "Qwen local semantic edit"
        case .largeLocalEditor: return "Qwen deep local edit"
        case .rawFallback: return "Raw safety fallback"
        }
    }

    private var outputRoute: String {
        guard let delivery = model.lastDictationDelivery else { return runtime.outputRoute }
        return delivery.outputRoute?.displayName ?? delivery.state.rawValue
    }

    private var liveUnstableText: String {
        guard let snapshot = model.streamingVoiceSession else { return runtime.unstableText }
        return snapshot.transcript.unstableText.isEmpty
            ? "None"
            : snapshot.transcript.unstableText
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
                Toggle(
                    "Use active-app context",
                    isOn: Binding(
                        get: { model.isVoiceContextEnabled },
                        set: { model.setVoiceContextEnabled($0) }
                    )
                )
                .font(.caption)
                .padding(.vertical, 9)
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

    private var qualityEvidence: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionLabel("QUALITY EVIDENCE", icon: "checkmark.seal")
            if let error = model.voiceQualityAuditError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .openLoopPanel()
            } else if let audit = model.voiceQualityAudit {
                VStack(spacing: 0) {
                    InspectorFact(label: "Claim status", value: qualityStatus(audit.status))
                    Divider()
                    InspectorFact(
                        label: "Corrected cases",
                        value: "\(audit.evaluatedCaseCount) / \(audit.totalCaseCount)"
                    )
                    Divider()
                    InspectorFact(label: "Word error", value: percentage(audit.report.wordErrorRate))
                    Divider()
                    InspectorFact(
                        label: "Hindi character error",
                        value: percentage(audit.report.devanagariCharacterErrorRate)
                    )
                    Divider()
                    InspectorFact(
                        label: "Term recall",
                        value: percentage(audit.report.domainTermRecall)
                    )
                    Divider()
                    InspectorFact(
                        label: "Stop → final p95",
                        value: milliseconds(audit.report.stopToFinalP95Milliseconds)
                    )
                }
                .padding(.horizontal, 12)
                .openLoopPanel(emphasized: audit.status == .readyForComparativeBenchmark)

                Text(qualityExplanation(audit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView("Auditing corrected local evidence…")
                    .font(.caption)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .openLoopPanel()
            }
        }
    }

    private func qualityStatus(_ status: VoiceQualityClaimStatus) -> String {
        switch status {
        case .unproven: "Unproven"
        case .thresholdsBlocked: "Blocked by evidence"
        case .readyForComparativeBenchmark: "Ready to benchmark"
        }
    }

    private func qualityExplanation(_ audit: VoiceQualityCorpusAudit) -> String {
        switch audit.status {
        case .unproven:
            "Representative corrected English, Hindi, and code-switched cases are still missing. No superiority claim is permitted."
        case .thresholdsBlocked:
            "The corrected corpus is representative, but \(audit.thresholdViolations.count) internal threshold(s) still fail."
        case .readyForComparativeBenchmark:
            "Internal thresholds pass. A controlled comparison against external products is still required before any superiority claim."
        }
    }

    private func percentage(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.percent.precision(.fractionLength(1)))
    }

    private func milliseconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded())) ms"
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
                ? "The active recognizer detects spoken language from each recording."
                : "Temporary override for this app session.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .padding(.vertical, 8)
    }
}
