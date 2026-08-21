import ADHDCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceDestination: Equatable, Sendable {
    let title: String
    let icon: String
}

enum WorkspaceOrientation {
    static let destinations = [
        WorkspaceDestination(title: "Live", icon: "waveform.circle"),
        WorkspaceDestination(title: "Context", icon: "point.3.connected.trianglepath.dotted"),
        WorkspaceDestination(title: "Emerging", icon: "sparkles"),
        WorkspaceDestination(title: "Ask", icon: "text.magnifyingglass"),
        WorkspaceDestination(title: "Act", icon: "bolt.circle"),
    ]
    static let quickCaptureShortcut = "⌘⇧Space  Quick Capture"
    static let voiceCaptureShortcut = "⌘⇧R  Record & transcribe"
    static let emptyCaptureGuidance = "Type above or press Command-Shift-Space from anywhere."
}

private struct MainView: View {
    @ObservedObject var model: AppModel
    @State var selection = 0
    @State private var interruptionItem: NowItem?
    @State private var memoryHistoryExpanded = false
    @State private var quickAddText = ""
    @State private var privacyExpanded = false
    @State private var confirmingReset = false
    @State private var actSection = 0
    @FocusState private var recallFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            OpenLoopVisualSystem.canvas.ignoresSafeArea()
            HStack(spacing: 0) {
                workspaceSidebar
                Divider().opacity(0.55)
                selectedSurface
                    .padding(.horizontal, 30)
                    .padding(.vertical, 27)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if model.isAdvancedModeEnabled {
                    Divider().opacity(0.55)
                    AdvancedInspector(
                        model: model,
                        selectedDestination: WorkspaceOrientation.destinations[selection]
                    )
                    .frame(width: 310)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(minWidth: model.isAdvancedModeEnabled ? 1120 : 820, minHeight: 600)
        .tint(OpenLoopVisualSystem.accent)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.22),
            value: model.isAdvancedModeEnabled
        )
        .task { await model.refresh() }
        .onChange(of: selection) { _, tab in
            if tab == 3 {
                recallFieldFocused = true
            }
            if tab == 1 { Task { await model.refreshMemory() } }
            if tab == 1 || tab == 2 || tab == 3 {
                Task { await model.refreshSemanticGraph() }
            }
        }
        .sheet(isPresented: interruptionPresented) {
            if let item = interruptionItem {
                InterruptionSheet(model: model, item: item) {
                    interruptionItem = nil
                }
            }
        }
        .alert("Remove all OpenLoop data?", isPresented: $confirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Remove everything", role: .destructive) {
                Task { await model.resetAllData() }
            }
        } message: {
            Text("This removes captures, tasks, memories, context, and the Recall index from this Mac. This cannot be undone.")
        }
    }

    @ViewBuilder private var selectedSurface: some View {
        switch selection {
        case 1: contextView
        case 2: emergingView
        case 3: askView
        case 4: actView
        default: nowView
        }
    }

    private var workspaceSidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(OpenLoopVisualSystem.accent)
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("OpenLoop")
                        .font(.headline.weight(.semibold))
                    Text("Working memory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 5) {
                ForEach(Array(WorkspaceOrientation.destinations.enumerated()), id: \.offset) { index, destination in
                    WorkspaceSidebarButton(
                        title: destination.title,
                        icon: destination.icon,
                        count: sidebarCount(for: index),
                        isSelected: selection == index
                    ) { selection = index }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    isOn: Binding(
                        get: { model.isAdvancedModeEnabled },
                        set: { model.setAdvancedModeEnabled($0) }
                    )
                ) {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                        .font(.callout.weight(.medium))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Show the local engine, pipeline, storage, and recent activity")

                Divider()
                Label(WorkspaceOrientation.quickCaptureShortcut, systemImage: "keyboard")
                Label(WorkspaceOrientation.voiceCaptureShortcut, systemImage: "waveform")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 218)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(OpenLoopVisualSystem.sidebar)
    }

    private func sidebarCount(for destination: Int) -> Int? {
        let count = switch destination {
        case 1: model.semanticNodes.count
        case 2: model.emergingThreads.count + model.unresolvedSemanticNodes.count
        case 4: model.openLoops.count + model.returns.count + model.reviewItems.count
        default: 0
        }
        return count == 0 ? nil : count
    }

    private var interruptionPresented: Binding<Bool> {
        Binding(
            get: { interruptionItem != nil },
            set: { if $0 == false { interruptionItem = nil } }
        )
    }

    private var nowView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ScreenHeader(
                    eyebrow: "VOICE + CAPTURE",
                    title: "Live",
                    detail: "Speak, import a meeting, or capture a thought. Processing stays visible and local."
                )

                if let notice = model.recoveryNotice {
                    StatusBanner(text: notice, icon: "checkmark.shield")
                }

                QuickAddComposer(model: model, text: $quickAddText) {
                    let captured = await model.submitCapture(quickAddText)
                    if captured { quickAddText = "" }
                }
                if model.meetingJob.stage != nil {
                    MeetingJobPanel(model: model)
                }
                CaptureCapabilityNote(summary: model.capabilitySummary)

                if let item = model.now, item.focus != nil {
                    currentIntention(item)
                } else if model.openLoops.contains(where: { $0.state == .open }) {
                    readyQueue
                } else if model.suggestions.isEmpty {
                    ContentUnavailableView(
                        model.returns.isEmpty ? "Nothing active" : "Your place is saved",
                        systemImage: model.returns.isEmpty
                            ? "circle.dashed"
                            : "arrow.uturn.backward.circle",
                        description: Text(
                            model.returns.isEmpty
                                ? WorkspaceOrientation.emptyCaptureGuidance
                                : "Open Return when you are ready to continue."
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 330)
                }

                if model.now?.focus != nil { contextTrailPanel }

                if model.suggestions.isEmpty == false {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("RELEVANT HERE")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("A linked open loop, shown without a notification.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.suggestions) { suggestion in
                        ContextSuggestionView(model: model, suggestion: suggestion)
                    }
                    Text("1 explicit app match required · 4-hour cooldown · up to 2")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(
                            "Suggestion algorithm: one explicit application match required, "
                                + "four hour cooldown, up to two suggestions"
                        )
                }

                if let error = model.commandError ?? model.resurfacingError {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var readyQueue: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose your next move")
                    .font(.title2.weight(.semibold))
                Text("Starting one moves it into focus. The order is yours.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)

            ForEach(model.openLoops.filter { $0.state == .open }) { item in
                ReadyTaskRow(model: model, item: item)
                Divider()
            }
        }
        .padding(18)
        .openLoopPanel()
    }

    private func currentIntention(_ item: NowItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("CURRENT INTENTION")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.desiredOutcome)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("NEXT ACTION")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.nextAction)
                    .font(.title3)
                    .textSelection(.enabled)
            }
            if item.focus != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(ElapsedCue.text(seconds: item.elapsed(at: context.date)))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            focusControls(item)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(OpenLoopVisualSystem.accent.opacity(0.78))
                .frame(width: 3)
        }
        .openLoopPanel(emphasized: true)
    }

    private var contextTrailPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Context trail")
                        .font(.title3.weight(.semibold))
                    Text("Application names only · active focus only · 8-hour maximum")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    "Keep an application trail during focus",
                    isOn: Binding(
                        get: { model.contextTrailSettings.isEnabled },
                        set: { enabled in
                            Task { await model.setContextTrailEnabled(enabled) }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(model.isUpdatingContextTrail)
                .accessibilityLabel("Keep an application trail during focus")
            }

            contextTrailContent

            if let error = model.contextTrailError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var contextTrailContent: some View {
        if !model.contextTrailSettings.isEnabled {
            Label("Private Mode is on. Nothing is observed or retained.", systemImage: "lock.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if model.now?.focus == nil {
            Label("Start focus to begin a private application trail.", systemImage: "circle.dotted")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if model.now?.focus?.state == .paused {
            Label("Focus is paused. No new context is being recorded.", systemImage: "pause.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if model.contextEpisodes.isEmpty {
            Label("Waiting for an app switch. OpenLoop records no window or document names.", systemImage: "arrow.triangle.branch")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 9) {
                    ForEach(Array(model.contextEpisodes.enumerated()), id: \.element.id) { index, episode in
                        if index > 0 {
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        ContextEpisodeNode(episode: episode)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private func focusControls(_ item: NowItem) -> some View {
        HStack(spacing: 10) {
            if let focus = item.focus {
                if focus.state == .active {
                    Button("Pause") { Task { await model.pauseFocus(item.intentionID) } }
                } else if focus.state == .paused {
                    Button("Continue") { Task { await model.continueFocus(item.intentionID) } }
                        .buttonStyle(.borderedProminent)
                }
                Button("Interrupt") { interruptionItem = item }
                Button("Finish") { Task { await model.finishFocus(item.intentionID) } }
            } else {
                Button("Start focus") { Task { await model.startFocus(item.intentionID) } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var returnView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(
                eyebrow: "RECOVERY",
                title: "Return",
                detail: "Exact restart points saved before an interruption."
            )
            if let error = model.commandError {
                Text(error).font(.callout).foregroundStyle(.secondary)
            }
            if model.returns.isEmpty {
                ContentUnavailableView(
                    "No saved return points",
                    systemImage: "arrow.uturn.backward.circle"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(model.returns) { item in
                            ReturnPacketView(model: model, item: item)
                        }
                    }
                }
            }
        }
    }

    private var laterView: some View {
        let needsDecision = model.reviewItems.filter(\.needsDecision)
        let heldSafely = model.reviewItems.filter { $0.needsDecision == false }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                ScreenHeader(
                    eyebrow: "DECIDE",
                    title: "Later",
                    detail: "Clarify, edit, order, finish, or release. Nothing here is overdue."
                )

                if let error = model.reviewError {
                    Label(error, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if model.reviewItems.isEmpty {
                ContentUnavailableView(
                    "Nothing stored yet",
                    systemImage: "tray",
                        description: Text("Captures you want to decide on or hold safely will appear here.")
                )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    if needsDecision.isEmpty == false {
                        reviewSection(
                            title: "Needs a decision",
                            detail: "OpenLoop left these unforced. Choose only when the meaning is clear.",
                            items: needsDecision
                        )
                    }
                    if heldSafely.isEmpty == false {
                        reviewSection(
                            title: "Held safely",
                            detail: "Actions, memories, and later thoughts stay editable until work begins.",
                            items: heldSafely
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 16)
        }
    }

    private func reviewSection(
        title: String,
        detail: String,
        items: [ClarificationReviewItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            Divider()
            ForEach(items) { item in
                ClarificationReviewRow(
                    model: model,
                    item: item,
                    openLoop: model.openLoops.first { $0.sourceCaptureID == item.id }
                )
                Divider()
            }
        }
    }

    private var askView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: "QUERY",
                    title: "Ask your context",
                    detail: "Search what OpenLoop understands, then inspect the original evidence."
                )

                semanticAskPanel

                meetingTranscriptSection { evidenceID in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(evidenceID, anchor: .center)
                    }
                }
                workingMemorySection
                privacySection

                HStack(spacing: 10) {
                    TextField("Search captures, decisions, return points, and corrections", text: $model.recallQuery)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .focused($recallFieldFocused)
                        .onSubmit { Task { await model.searchRecall(model.recallQuery) } }
                    Button("Search") {
                        Task { await model.searchRecall(model.recallQuery) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.recallQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack {
                    Text("⌘⇧F opens Ask")
                    Spacer()
                    Text("Exact + local semantic evidence")
                }
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)

                if model.isRecalling {
                    ProgressView("Searching on this Mac…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let error = model.recallError {
                    ContentUnavailableView(
                        "Recall paused",
                        systemImage: "magnifyingglass",
                        description: Text(error)
                    )
                } else if model.recallQuery.isEmpty {
                    ContentUnavailableView(
                        "Search your evidence",
                        systemImage: "text.magnifyingglass",
                        description: Text("Try a name, exact phrase, decision, or restart action.")
                    )
                } else if model.recallHits.isEmpty {
                    ContentUnavailableView(
                        "No matching evidence",
                        systemImage: "magnifyingglass",
                        description: Text("OpenLoop will not invent an answer.")
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.recallHits) { hit in
                            RecallEvidenceRow(hit: hit)
                            Divider()
                        }
                    }
                    .background(
                        Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                recallFieldFocused = true
                Task {
                    await model.refreshPrivacy()
                    _ = await model.refresh()
                }
            }
        }
    }

    private var semanticAskPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SEMANTIC GRAPH")
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                TextField("What have I been thinking about?", text: $model.semanticQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.askSemanticContext(model.semanticQuery) } }
                Button("Ask locally") {
                    Task { await model.askSemanticContext(model.semanticQuery) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.semanticQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error = model.semanticError {
                Label(error, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if model.semanticQuery.isEmpty {
                Text("Answers are matched locally and always keep their evidence attached.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if model.semanticAnswers.isEmpty {
                Text("No grounded answer found. OpenLoop will not invent one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.semanticAnswers) { node in
                    SemanticNodeRow(node: node, showEvidence: true)
                }
            }
        }
        .padding(14)
        .openLoopPanel(emphasized: !model.semanticAnswers.isEmpty)
    }

    private var contextView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: "UNDERSTANDING",
                    title: "Context",
                    detail: "Evidence-grounded observations, concepts, people, projects, and decisions."
                )
                if model.isRefreshingSemanticGraph {
                    ProgressView("Rebuilding context locally…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let error = model.semanticError {
                    ContentUnavailableView(
                        "Context paused",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text(error)
                    )
                } else if model.semanticNodes.isEmpty {
                    ContentUnavailableView(
                        "No semantic context yet",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Capture naturally in Live. OpenLoop will preserve the evidence before deriving meaning.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.semanticNodes) { node in
                            SemanticNodeRow(node: node, showEvidence: true)
                            Divider()
                        }
                    }
                    .padding(.horizontal, 14)
                    .openLoopPanel()
                }
                workingMemorySection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 16)
        }
        .task {
            await model.refreshSemanticGraph()
            await model.refreshMemory()
        }
    }

    private var emergingView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: "PATTERNS",
                    title: "Emerging",
                    detail: "Repeated themes and unresolved thinking surface quietly. Nothing becomes a task automatically."
                )
                if model.emergingThreads.isEmpty && model.unresolvedSemanticNodes.isEmpty {
                    ContentUnavailableView(
                        "No pattern is strong enough yet",
                        systemImage: "sparkles",
                        description: Text("OpenLoop waits for grounded recurrence instead of generating productivity noise.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    if !model.unresolvedSemanticNodes.isEmpty {
                        SemanticSectionTitle(
                            title: "Unresolved",
                            detail: "Active questions and problems with no confirmed resolution."
                        )
                        ForEach(model.unresolvedSemanticNodes) { node in
                            SemanticNodeRow(node: node, showEvidence: true)
                        }
                    }
                    if !model.emergingThreads.isEmpty {
                        SemanticSectionTitle(
                            title: "Threads",
                            detail: "Connected ideas ranked by evidence and relationships."
                        )
                        ForEach(model.emergingThreads) { thread in
                            SemanticThreadRow(thread: thread)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 16)
        }
        .task { await model.refreshSemanticGraph() }
    }

    private var actView: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(
                eyebrow: "EXECUTION",
                title: "Act",
                detail: "Choose an explicit next move. Suggestions remain reviewable until you approve them."
            )
            Picker("Action workspace", selection: $actSection) {
                Text("Ready").tag(0)
                Text("Return").tag(1)
                Text("Review").tag(2)
            }
            .pickerStyle(.segmented)

            switch actSection {
            case 1: returnView
            case 2: laterView
            default:
                if let item = model.now, item.focus != nil {
                    currentIntention(item)
                } else if model.openLoops.contains(where: { $0.state == .open }) {
                    readyQueue
                } else {
                    ContentUnavailableView(
                        "Nothing ready to act on",
                        systemImage: "bolt.circle",
                        description: Text("Potential actions stay in Emerging until you deliberately promote them.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder private func meetingTranscriptSection(
        onEvidence: @escaping (UUID) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.meetingTranscripts.isEmpty
                        ? "MEETING TRANSCRIPTS"
                        : "MEETING TRANSCRIPTS · \(model.meetingTranscripts.count)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Qwen accuracy · Whisper fallback · processed locally")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Import audio…") { presentMeetingImporter() }
                    .buttonStyle(.borderedProminent)
            }

            if model.meetingJob.stage != nil {
                MeetingJobPanel(model: model)
            }

            if model.meetingTranscripts.isEmpty && model.meetingJob.stage == nil {
                Text("Drop in a long meeting recording. The first run downloads a high-accuracy local model; your audio never leaves this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else if !model.meetingTranscripts.isEmpty {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(model.meetingTranscripts.enumerated()), id: \.element.id) { index, transcript in
                        MeetingTranscriptRow(
                            model: model,
                            transcript: transcript,
                            initiallyExpanded: index == 0,
                            onEvidence: onEvidence
                        )
                    }
                }
            }
        }
        .padding(14)
        .openLoopPanel(emphasized: true)
    }

    private func presentMeetingImporter() {
        let panel = NSOpenPanel()
        panel.title = "Choose a meeting recording"
        panel.prompt = "Transcribe locally"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mpeg4Movie]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.importMeetingAudio(url)
        }
    }

    private var privacySection: some View {
        DisclosureGroup("Privacy & storage", isExpanded: $privacyExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 20) {
                    PrivacyMetric(value: "\(model.privacySummary.captureCount)", label: "CAPTURES")
                    PrivacyMetric(value: "\(model.privacySummary.openIntentionCount)", label: "OPEN")
                    PrivacyMetric(value: "\(model.privacySummary.memoryCount)", label: "MEMORIES")
                    PrivacyMetric(
                        value: ByteCountFormatter.string(
                            fromByteCount: model.privacySummary.encryptedBytes,
                            countStyle: .file
                        ),
                        label: "ENCRYPTED"
                    )
                }

                HStack {
                    Text("Keep completed evidence")
                        .font(.callout)
                    Picker("Keep completed evidence", selection: Binding(
                        get: { model.retentionPolicy },
                        set: { policy in Task { await model.applyRetention(policy) } }
                    )) {
                        Text("Forever").tag(PrivacyRetentionPolicy.keepForever)
                        Text("90 days").tag(PrivacyRetentionPolicy.ninetyDays)
                        Text("30 days").tag(PrivacyRetentionPolicy.thirtyDays)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    Spacer()
                }

                Text("Backups contain only the encrypted vault, not its key, so they restore on this Mac with the same OpenLoop key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Save encrypted backup…") { saveEncryptedBackup() }
                    Button("Remove all data…", role: .destructive) { confirmingReset = true }
                    Spacer()
                }
                .disabled(model.isUpdatingPrivacy)

                if let message = model.privacyError ?? model.privacyNotice {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 12)
        }
        .font(.callout.weight(.medium))
        .padding(14)
        .openLoopPanel()
    }

    private func saveEncryptedBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "OpenLoop Backup.openloopvault"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await model.createEncryptedBackup(at: url) }
        }
    }

    @ViewBuilder private var workingMemorySection: some View {
        let current = model.memoryRecords.filter { record in
            switch record.state {
            case .active, .contradicted: true
            case .superseded, .evidenceExpired: false
            }
        }
        let history = model.memoryRecords.filter { !current.map(\.id).contains($0.id) }

        if model.isCompilingMemory || !model.memoryRecords.isEmpty || model.memoryError != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WORKING MEMORY")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text("Explicit claims linked to stored evidence")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Refresh evidence") {
                        Task { await model.refreshMemory() }
                    }
                    .buttonStyle(.link)
                    .disabled(model.isCompilingMemory)
                }

                if model.isCompilingMemory && model.memoryRecords.isEmpty {
                    ProgressView("Checking explicit memory…")
                        .controlSize(.small)
                }

                if !model.memoryRecords.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(current) { record in
                                WorkingMemoryRow(record: record)
                            }

                            if !history.isEmpty {
                                DisclosureGroup("History", isExpanded: $memoryHistoryExpanded) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(history) { record in
                                            WorkingMemoryRow(record: record)
                                        }
                                    }
                                    .padding(.top, 7)
                                }
                                .font(.callout)
                            }
                        }
                    }
                    .frame(maxHeight: 170)
                }

                if let error = model.memoryError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 4)
            Divider()
        }
    }

    private func openLoopStateLabel(_ state: IntentionState) -> String {
        switch state {
        case .active: "Focusing"
        case .open: "Ready"
        case .interrupted: "Return point saved"
        case .closed: "Finished"
        case .released: "Released"
        }
    }
}

private struct ScreenHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(OpenLoopVisualSystem.accent)
            Text(title)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .tracking(-0.7)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }
}

private struct WorkspaceSidebarButton: View {
    let title: String
    let icon: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 17)
                    .foregroundStyle(isSelected ? OpenLoopVisualSystem.accent : .secondary)
                Text(title)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(
                isSelected ? OpenLoopVisualSystem.accentSoft : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(OpenLoopVisualSystem.accent)
                        .frame(width: 3, height: 18)
                        .offset(x: -1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct QuickAddComposer: View {
    @ObservedObject var model: AppModel
    @Binding var text: String
    let submit: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Capture anything", systemImage: "plus.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(OpenLoopVisualSystem.accent)
                Spacer()
                Text("TEXT · AUDIO · MEETING")
                    .font(.caption2.monospaced().weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            HStack(alignment: .center, spacing: 10) {
                TextField("What should OpenLoop hold for you?", text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.medium))
                    .padding(.horizontal, 13)
                    .frame(height: 42)
                    .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(OpenLoopVisualSystem.hairline, lineWidth: 1)
                    }
                    .onSubmit { Task { await submit() } }
                Button(isSaving ? "Saving…" : "Capture") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button {
                    model.toggleVoiceCapture()
                } label: {
                    Label(
                        model.meetingJob.stage == .recording ? "Stop & transcribe" : "Record",
                        systemImage: model.meetingJob.stage == .recording
                            ? "stop.circle.fill"
                            : "record.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(model.meetingJob.stage == .recording ? .red : OpenLoopVisualSystem.accent)
                .disabled(model.meetingJob.isActive && model.meetingJob.stage != .recording)
            }
            if model.meetingJob.stage == .recording {
                RecordingLevelMeter(decibels: model.recordingDecibels)
                if let snapshot = model.streamingVoiceSession,
                   !snapshot.transcript.visibleText.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        if !snapshot.transcript.stableText.isEmpty {
                            Text(snapshot.transcript.stableText)
                                .foregroundStyle(.primary)
                        }
                        if !snapshot.transcript.unstableText.isEmpty {
                            Text(snapshot.transcript.unstableText)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityLabel("Live transcription")
                }
            }
            HStack(spacing: 10) {
                Button("Import meeting audio…", systemImage: "waveform.badge.plus") {
                    presentMeetingImporter()
                }
                .buttonStyle(.borderless)
                .disabled(model.meetingJob.isActive)
                Spacer()
                Text("Processed and encrypted on this Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(17)
        .openLoopPanel(emphasized: model.meetingJob.isActive)
    }

    private var isSaving: Bool { model.isSaving }

    private func presentMeetingImporter() {
        let panel = NSOpenPanel()
        panel.title = "Choose a meeting recording"
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

private struct RecordingLevelMeter: View {
    let decibels: Float?

    private let barCount = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                Text("MIC INPUT")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.red)
                Text(signalStatus)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(decibelText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
            }

            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(barColor(index: index))
                        .frame(width: 4, height: barHeight(index: index))
                }
            }
            .frame(height: 30)
            .animation(.linear(duration: 0.06), value: decibels)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.red.opacity(0.065), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.red.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone input")
        .accessibilityValue("\(decibelText), \(signalStatus)")
    }

    private var normalizedLevel: CGFloat {
        guard let decibels else { return 0 }
        return CGFloat(min(1, max(0, (decibels + 60) / 60)))
    }

    private var decibelText: String {
        guard let decibels else { return "— dB" }
        return String(format: "%.0f dB", decibels)
    }

    private var signalStatus: String {
        guard let decibels else { return "LISTENING" }
        if decibels < -45 { return "SIGNAL LOW" }
        if decibels < -28 { return "HEARING YOU" }
        return "STRONG SIGNAL"
    }

    private func barHeight(index: Int) -> CGFloat {
        let phase = Double(index) * 1.47
        let profile = CGFloat(0.52 + 0.48 * abs(sin(phase)))
        return max(4, (6 + 24 * normalizedLevel) * profile)
    }

    private func barColor(index: Int) -> Color {
        let threshold = Int((normalizedLevel * CGFloat(barCount)).rounded())
        return index < threshold ? .red : .secondary.opacity(0.16)
    }
}

private struct MeetingJobPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(model.meetingJob.stage == .recording ? .red : .primary)
                Spacer()
                Text("LOCAL ONLY")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.green)
                if model.meetingJob.requestedLanguage != .automatic {
                    Text(model.meetingJob.requestedLanguage.title.uppercased())
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(OpenLoopVisualSystem.accent)
                }
            }
            Text(model.meetingJob.message)
                .font(.callout)
                .foregroundStyle(.secondary)
            if model.meetingJob.stage != .recording, let captureSummary {
                Label(captureSummary, systemImage: "waveform.path.ecg")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if model.meetingJob.stage == .recording {
                RecordingLevelMeter(decibels: model.recordingDecibels)
                HStack {
                    Text(model.meetingJob.sourceName ?? "Live recording")
                    Spacer()
                    if let startedAt = model.meetingJob.startedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(elapsed(startedAt, context.date))
                        }
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            } else if model.meetingJob.isActive {
                ProgressView(value: model.meetingJob.fraction)
                HStack {
                    Text(model.meetingJob.sourceName ?? "Audio recording")
                    Spacer()
                    if let startedAt = model.meetingJob.startedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(elapsed(startedAt, context.date))
                        }
                    }
                    Text("\(Int(model.meetingJob.fraction * 100))%")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
            if let transcriptText {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(
                            model.meetingJob.stage == .ready ? "Transcript" : "Live transcript",
                            systemImage: "text.quote"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OpenLoopVisualSystem.accent)
                        Spacer()
                        Button("Copy") { copy(transcriptText) }
                            .buttonStyle(.link)
                    }
                    ScrollView {
                        Text(transcriptText)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 54, maxHeight: model.meetingJob.stage == .ready ? 260 : 140)
                }
                .padding(11)
                .background(.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(OpenLoopVisualSystem.hairline, lineWidth: 1)
                }
            }
            HStack(spacing: 10) {
                if model.meetingJob.isActive {
                    Button("Cancel") { model.cancelMeetingTranscription() }
                } else if model.meetingJob.canRetry {
                    Button(
                        model.meetingJob.stage == .ready
                            ? "Retranscribe source"
                            : "Retry locally"
                    ) { model.retryMeetingTranscription() }
                        .buttonStyle(.borderedProminent)
                }
                if !model.meetingJob.isActive {
                    Button(
                        model.meetingJob.stagedAudioURL == nil
                            ? "Dismiss"
                            : "Dismiss & discard audio"
                    ) { model.clearMeetingJob() }
                        .buttonStyle(.link)
                }
                Spacer()
                if let modelName = model.meetingJob.modelIdentifier {
                    Text(modelName)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(13)
        .openLoopPanel(emphasized: model.meetingJob.isActive)
        .accessibilityLabel("Local meeting transcription: \(model.meetingJob.message)")
    }

    private var transcriptText: String? {
        if model.meetingJob.stage == .ready,
           let completedID = model.meetingJob.completedTranscriptID,
           let completed = model.meetingTranscripts.first(where: { $0.id == completedID })?.text {
            return completed
        }
        return model.meetingJob.previewText
    }

    private var captureSummary: String? {
        guard let duration = model.meetingJob.recordingDuration else { return nil }
        let durationText = duration < 10
            ? String(format: "%.1fs", duration)
            : "\(Int(duration.rounded()))s"
        if let peak = model.meetingJob.recordingPeakDecibels {
            return "RECORDED \(durationText) · PEAK \(Int(peak.rounded())) dB"
        }
        return "RECORDED \(durationText) · NO LEVEL DATA"
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var title: String {
        switch model.meetingJob.stage {
        case .requestingMicrophone: "Requesting microphone"
        case .recording: "Recording meeting"
        case .waitingForModel: "Preparing model"
        case .downloadingModel: "Downloading accuracy model"
        case .preparingAudio: "Preparing audio"
        case .transcribing: "Transcribing meeting"
        case .diarizing: "Separating speakers"
        case .saving: "Encrypting transcript"
        case .ready: "Transcript ready"
        case .failed: "Transcription needs attention"
        case .cancelled: "Transcription cancelled"
        case nil: "Meeting transcription"
        }
    }

    private var icon: String {
        switch model.meetingJob.stage {
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle"
        case .cancelled: "xmark.circle"
        default: "waveform.and.mic"
        }
    }

    private func elapsed(_ start: Date, _ end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct MeetingTranscriptRow: View {
    @ObservedObject var model: AppModel
    let transcript: MeetingTranscript
    let onEvidence: (UUID) -> Void
    @State private var expanded: Bool
    @State private var selectedEvidenceID: UUID?
    @State private var editingSegmentID: UUID?
    @State private var correctionDraft = ""

    init(
        model: AppModel,
        transcript: MeetingTranscript,
        initiallyExpanded: Bool = false,
        onEvidence: @escaping (UUID) -> Void = { _ in }
    ) {
        self.model = model
        self.transcript = transcript
        self.onEvidence = onEvidence
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if expanded {
                VStack(alignment: .leading, spacing: 16) {
                    meetingBrief { insight in
                        selectedEvidenceID = insight.evidence.segmentID
                        onEvidence(insight.evidence.segmentID)
                    }

                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            Text("Transcript")
                                .font(.headline)
                            Spacer()
                            Text("EVIDENCE")
                                .font(.caption2.monospaced().weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        ForEach(transcript.segments) { segment in
                            HStack(alignment: .top, spacing: 10) {
                                Text(timestamp(segment.start))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 44, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 2) {
                                    if let speaker = segment.speaker {
                                        Text(speaker.uppercased())
                                            .font(.caption2.monospaced().weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    if editingSegmentID == segment.id {
                                        TextEditor(text: $correctionDraft)
                                            .font(.callout)
                                            .frame(minHeight: 64)
                                            .padding(5)
                                            .background(
                                                Color(nsColor: .textBackgroundColor).opacity(0.5),
                                                in: RoundedRectangle(cornerRadius: 7)
                                            )
                                        HStack {
                                            Button("Save correction") {
                                                Task {
                                                    if await model.correctMeetingSegment(
                                                        transcriptID: transcript.id,
                                                        segmentID: segment.id,
                                                        correctedText: correctionDraft
                                                    ) {
                                                        editingSegmentID = nil
                                                    }
                                                }
                                            }
                                            .disabled(correctionDraft.trimmingCharacters(
                                                in: .whitespacesAndNewlines
                                            ).isEmpty)
                                            Button("Cancel") { editingSegmentID = nil }
                                        }
                                        .buttonStyle(.borderless)
                                    } else {
                                        Text(segment.text)
                                            .font(.callout)
                                            .textSelection(.enabled)
                                        Button("Correct transcript") {
                                            correctionDraft = segment.text
                                            editingSegmentID = segment.id
                                        }
                                        .font(.caption)
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(
                                selectedEvidenceID == segment.id
                                    ? OpenLoopVisualSystem.accentSoft
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .id(segment.id)
                        }
                    }

                    HStack {
                        Button("Copy transcript") { copy(transcript.text) }
                        Button("Send transcript to Review") {
                            Task { await model.captureMeetingTranscript(transcript.id) }
                        }
                        Button("Delete", role: .destructive) {
                            Task { await model.deleteMeetingTranscript(transcript.id) }
                        }
                        Spacer()
                    }
                }
                .padding(.top, 12)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(transcript.sourceName)
                        .font(.callout.weight(.medium))
                    Text("\(duration(transcript.duration)) · \(transcript.detectedLanguage?.uppercased() ?? "AUTO") · \(transcript.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(expanded
                        ? MeetingIntelligencePresentation.countLabel(for: intelligence)
                        : "Open for local meeting brief")
                        .font(.caption2)
                        .foregroundStyle(OpenLoopVisualSystem.accent)
                }
            }
        }
        .padding(11)
        .openLoopPanel()
    }

    private var intelligence: MeetingIntelligence {
        MeetingIntelligenceCompiler().compile(transcript)
    }

    @ViewBuilder
    private func meetingBrief(onEvidence: @escaping (MeetingInsight) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Meeting brief", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(OpenLoopVisualSystem.accent)
                    Text("Evidence-ranked and verbatim — no cloud processing, no invented tasks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("LOCAL · EXTRACTIVE")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(OpenLoopVisualSystem.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(OpenLoopVisualSystem.accentSoft, in: Capsule())
            }

            briefSection(
                title: "Summary",
                icon: "text.quote",
                insights: intelligence.summary,
                emptyText: "Not enough speech to form a useful summary.",
                onEvidence: onEvidence
            )

            HStack(alignment: .top, spacing: 12) {
                briefSection(
                    title: "Decisions",
                    icon: "checkmark.seal",
                    insights: intelligence.decisions,
                    emptyText: MeetingIntelligencePresentation.emptyDecisionText,
                    onEvidence: onEvidence
                )
                briefSection(
                    title: "Action candidates",
                    icon: "arrow.up.right.circle",
                    insights: intelligence.actionCandidates,
                    emptyText: MeetingIntelligencePresentation.emptyActionText,
                    onEvidence: onEvidence
                )
            }

            Label(
                "Action candidates stay here until you review them; OpenLoop does not add them to Now automatically.",
                systemImage: "hand.raised"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(OpenLoopVisualSystem.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(OpenLoopVisualSystem.accent.opacity(0.16), lineWidth: 1)
        }
    }

    private func briefSection(
        title: String,
        icon: String,
        insights: [MeetingInsight],
        emptyText: String,
        onEvidence: @escaping (MeetingInsight) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if insights.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(insights) { insight in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(insight.text)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            Button(MeetingIntelligencePresentation.evidenceLabel(for: insight)) {
                                onEvidence(insight)
                            }
                            .buttonStyle(.link)
                            .font(.caption.monospacedDigit())
                            Button("Copy") { copy(insight.text) }
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }
                    .padding(9)
                    .background(.background.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(OpenLoopVisualSystem.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func timestamp(_ seconds: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return total >= 3_600
            ? String(format: "%d:%02d:%02d", total / 3_600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct VoiceInlineStatus: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            indicator
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(statusTitle)
                        .font(.callout.weight(.medium))
                    if model.voiceCapture.state == .recording,
                       let startedAt = model.voiceCapture.startedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(elapsed(from: startedAt, to: context.date))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !model.voiceCapture.statusMessage.isEmpty {
                    Text(model.voiceCapture.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !model.voiceCapture.transcript.isEmpty {
                    Text(model.voiceCapture.transcript)
                        .font(.callout)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            if model.voiceCapture.state == .recording || model.voiceCapture.state == .failed {
                Button("Cancel") { model.cancelVoiceCapture() }
                    .buttonStyle(.link)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var indicator: some View {
        switch model.voiceCapture.state {
        case .recording:
            Circle().fill(Color.red).frame(width: 9, height: 9)
        case .requestingPermission, .saving:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    private var statusTitle: String {
        switch model.voiceCapture.state {
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

private struct CaptureCapabilityNote: View {
    let summary: CapabilitySummary

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.shield")
            Text(note)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var note: String {
        if summary.quickCapture == .unavailable {
            return "Typed capture is ready here. The global shortcut is unavailable."
        }
        if summary.microphone == .unavailable {
            return "Audio import is ready. Live recording is disabled in macOS microphone settings."
        }
        if summary.microphone == .askWhenUsed {
            return "Audio import is permission-free. Recording asks for microphone access only when first used."
        }
        return "Typed, imported, and recorded capture stay on this Mac."
    }
}

private struct StatusBanner: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .openLoopPanel(emphasized: true)
    }
}

private struct ReadyTaskRow: View {
    @ObservedObject var model: AppModel
    let item: OpenLoopItem

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.desiredOutcome)
                    .font(.headline)
                Text(item.nextAction)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 14)
            Button("Start") { Task { await model.startFocus(item.id) } }
                .buttonStyle(.borderedProminent)
            Menu {
                Button("Move up") { Task { await model.moveOpenLoop(item.id, by: -1) } }
                Button("Move down") { Task { await model.moveOpenLoop(item.id, by: 1) } }
                Divider()
                Button("Finish") { Task { await model.finishOpenLoop(item.id) } }
                Button("Release", role: .destructive) { Task { await model.releaseOpenLoop(item.id) } }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.vertical, 13)
    }
}

private struct PrivacyMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}

private struct ClarificationReviewRow: View {
    @ObservedObject var model: AppModel
    let item: ClarificationReviewItem
    let openLoop: OpenLoopItem?

    @State private var isEditing = false
    @State private var disposition: Disposition
    @State private var desiredOutcome: String
    @State private var nextAction: String

    init(model: AppModel, item: ClarificationReviewItem, openLoop: OpenLoopItem?) {
        self.model = model
        self.item = item
        self.openLoop = openLoop
        _disposition = State(initialValue: item.disposition)
        _desiredOutcome = State(initialValue: item.desiredOutcome ?? "")
        _nextAction = State(initialValue: item.nextAction ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.text)
                    .font(.title3.weight(.medium))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Text(dispositionLabel(item.disposition))
                    .font(.caption.monospaced().weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            if item.disposition == .action,
               let outcome = item.desiredOutcome,
               let action = item.nextAction {
                VStack(alignment: .leading, spacing: 5) {
                    Text(outcome)
                        .font(.callout.weight(.medium))
                    Label(action, systemImage: "arrow.forward")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if isEditing {
                editor
            } else {
                controls
            }
        }
        .padding(.vertical, 14)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keep this as")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("Keep this as", selection: $disposition) {
                    ForEach(reviewDispositions, id: \.self) { value in
                        Text(dispositionLabel(value)).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Spacer()
            }

            if disposition == .action {
                TextField("What would done look like?", text: $desiredOutcome)
                    .textFieldStyle(.roundedBorder)
                TextField("What is the smallest visible next action?", text: $nextAction)
                    .textFieldStyle(.roundedBorder)
            } else if disposition == .release {
                Text("Release removes this from Later. Its original encrypted capture remains available to Recall.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Cancel") {
                    resetDraft()
                    isEditing = false
                }
                Button("Save review") {
                    Task {
                        let saved = await model.applyClarificationReview(
                            captureID: item.id,
                            disposition: disposition,
                            desiredOutcome: disposition == .action ? desiredOutcome : nil,
                            nextAction: disposition == .action ? nextAction : nil
                        )
                        if saved { isEditing = false }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isSavingReview)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 12) {
            if let openLoop {
                if openLoop.state == .open {
                    Button("Start focus") {
                        Task { await model.startFocus(openLoop.intentionID) }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Finish") {
                    Task { await model.finishOpenLoop(openLoop.intentionID) }
                }

                Menu {
                    Button("Move up") {
                        Task { await model.moveOpenLoop(openLoop.intentionID, by: -1) }
                    }
                    Button("Move down") {
                        Task { await model.moveOpenLoop(openLoop.intentionID, by: 1) }
                    }
                    Divider()
                    Button("Release", role: .destructive) {
                        Task { await model.releaseOpenLoop(openLoop.intentionID) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)

                if openLoop.state == .open, let application = model.currentApplication {
                    Button(
                        model.isLinked(openLoop.intentionID, to: application)
                            ? "Stop suggesting here"
                            : "Suggest in \(application.applicationName)"
                    ) {
                        Task {
                            if model.isLinked(openLoop.intentionID, to: application) {
                                await model.unlinkSuggestion(openLoop.intentionID)
                            } else {
                                await model.linkSuggestion(openLoop.intentionID, to: application)
                            }
                        }
                    }
                    .buttonStyle(.link)
                }
            }

            if item.isEditable {
                if item.needsDecision {
                    Button("Decide") {
                        resetDraft()
                        isEditing = true
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Review") {
                        resetDraft()
                        isEditing = true
                    }
                    .buttonStyle(.bordered)
                }
            } else if let state = item.intentionState {
                Text(intentionStateLabel(state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var reviewDispositions: [Disposition] {
        [.action, .memory, .later, .release, .unclear]
    }

    private func resetDraft() {
        disposition = item.disposition
        desiredOutcome = item.desiredOutcome ?? ""
        nextAction = item.nextAction ?? ""
    }

    private func dispositionLabel(_ value: Disposition) -> String {
        switch value {
        case .action: "One action"
        case .memory: "Remember"
        case .later: "Consider later"
        case .release: "Release"
        case .unclear: "Not sure yet"
        }
    }

    private func intentionStateLabel(_ state: IntentionState) -> String {
        switch state {
        case .active: "In focus — review is paused"
        case .interrupted: "Return point saved — review is paused"
        case .open: "Ready"
        case .closed: "Finished"
        case .released: "Released"
        }
    }
}

private struct ContextEpisodeNode: View {
    let episode: ContextEpisode

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(episode.application.applicationName)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(episode.startedAt, style: .time)
                if episode.lastObservedAt != episode.startedAt {
                    Text("–")
                    Text(episode.lastObservedAt, style: .time)
                }
                if episode.observationCount > 1 {
                    Text("· \(episode.observationCount) signals")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color.accentColor.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }
}

private struct WorkingMemoryRow: View {
    let record: MemoryRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(record.statement)
                .font(.body)
                .textSelection(.enabled)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(record.kind.rawValue.uppercased()) · \(stateLabel)")
                Text(evidenceLabel)
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var stateLabel: String {
        switch record.state {
        case .active: "CURRENT"
        case .contradicted: "CONTRADICTED"
        case .superseded: "SUPERSEDED"
        case .evidenceExpired: "EVIDENCE EXPIRED"
        }
    }

    private var evidenceLabel: String {
        let retained = record.evidence.filter { $0.availability == .retained }.count
        let expired = record.evidence.count - retained
        if expired == 0 { return "\(retained) EVIDENCE RETAINED" }
        return "\(retained) RETAINED · \(expired) EXPIRED"
    }
}

private struct SemanticSectionTitle: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

private struct SemanticNodeRow: View {
    let node: SemanticNode
    let showEvidence: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(node.kind.rawValue.uppercased())
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(node.status == .speculative ? .orange : OpenLoopVisualSystem.accent)
                Spacer()
                Text("\(Int((node.confidence * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(node.claim)
                .font(.body.weight(.medium))
                .textSelection(.enabled)
            if showEvidence, let evidence = node.evidence.first {
                Label(evidence.excerpt, systemImage: "quote.opening")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            HStack(spacing: 7) {
                Text(node.status.rawValue.capitalized)
                Text("·")
                Text(node.createdAt, style: .relative)
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SemanticThreadRow: View {
    let thread: SemanticThread

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(thread.node.claim)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("STRENGTH \(thread.strength)")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if thread.related.isEmpty {
                Text("Grounded by \(thread.node.evidence.count) evidence item(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 6) {
                        ForEach(thread.related) { related in
                            Text(related.claim)
                                .font(.caption)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(OpenLoopVisualSystem.accentSoft, in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(14)
        .openLoopPanel()
    }
}

private struct RecallEvidenceRow: View {
    let hit: RecallHit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(hit.title).font(.headline)
                    Text(evidenceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(hit.occurredAt, style: .relative)
                    Text("Match \(hit.score, format: .number.precision(.fractionLength(2)))")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Text(hit.excerpt)
                .lineLimit(4)
                .textSelection(.enabled)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(hit.contributions) { contribution in
                    HStack(spacing: 8) {
                        Text(contributionLabel(contribution.kind))
                            .font(.caption)
                            .frame(width: 105, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.secondary.opacity(0.12))
                                Rectangle().fill(Color.accentColor.opacity(0.7))
                                    .frame(width: proxy.size.width * min(1, max(0, contribution.value)))
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var evidenceLabel: String {
        switch hit.evidenceID.kind {
        case .capture: "CAPTURE"
        case .intention: "INTENTION"
        case .returnPacket: "RETURN PACKET"
        case .correction: "VOICE CORRECTION"
        case .memory: "MEMORY"
        }
    }

    private func contributionLabel(_ kind: RecallContributionKind) -> String {
        switch kind {
        case .exactPhrase: "Exact phrase"
        case .tokenCoverage: "Shared words"
        case .semanticSimilarity: "Local meaning"
        }
    }
}

private struct ContextSuggestionView: View {
    @ObservedObject var model: AppModel
    let suggestion: ContextualSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(suggestion.desiredOutcome)
                    .font(.headline)
                Text(suggestion.nextAction)
                    .font(.title3)
                    .textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("WHY NOW · \(suggestion.why.uppercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(suggestion.contributions) { contribution in
                    RelevanceContributionBar(contribution: contribution)
                }
            }
            HStack(spacing: 10) {
                Button("Start") {
                    Task { await model.startSuggestion(suggestion.intentionID) }
                }
                .buttonStyle(.borderedProminent)
                Button("Later") {
                    Task { await model.deferSuggestion(suggestion.intentionID) }
                }
                Button("Never suggest") {
                    Task { await model.silenceSuggestion(suggestion.intentionID) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.accentColor.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}

private struct RelevanceContributionBar: View {
    let contribution: RelevanceContribution

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(contribution.label)
                    .font(.callout)
                Spacer()
                Text(contribution.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.14))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(
                            width: proxy.size.width * min(
                                1,
                                contribution.value / RelevanceScorer.threshold
                            )
                        )
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(contribution.label)
        .accessibilityValue(contribution.explanation)
    }
}

private struct InterruptionSheet: View {
    @ObservedObject var model: AppModel
    let item: NowItem
    let dismiss: () -> Void
    @State private var justCompleted = ""
    @State private var nextAction: String
    @State private var blocker = ""
    @State private var references = ""

    init(model: AppModel, item: NowItem, dismiss: @escaping () -> Void) {
        self.model = model
        self.item = item
        self.dismiss = dismiss
        _nextAction = State(initialValue: item.nextAction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Save your place")
                .font(.title2)
                .fontWeight(.semibold)
            Text("A small return packet is enough. Only the next action is required.")
                .foregroundStyle(.secondary)
            Form {
                TextField("Just completed", text: $justCompleted)
                TextField("Exact next action", text: $nextAction)
                TextField("Blocker or uncertainty", text: $blocker)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Files, links, or notes — one per line")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $references)
                        .font(.body.monospaced())
                        .frame(minHeight: 72)
                }
            }
            if let error = model.commandError {
                Text(error).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Keep focusing", action: dismiss)
                Button("Save and interrupt") {
                    Task {
                        let saved = await model.interruptFocus(
                            item.intentionID,
                            draft: InterruptionDraft(
                                justCompleted: justCompleted,
                                nextAction: nextAction,
                                blocker: blocker,
                                references: references.components(separatedBy: .newlines)
                            )
                        )
                        if saved { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

private struct ReturnPacketView: View {
    @ObservedObject var model: AppModel
    let item: ReturnItem

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                packetField("RETURN TO", item.desiredOutcome)
                if let justCompleted = item.justCompleted {
                    packetField("JUST COMPLETED", justCompleted)
                }
                packetField("NEXT ACTION", item.nextAction, prominent: true)
                if let blocker = item.blocker {
                    packetField("BLOCKER", blocker)
                }
                if item.references.isEmpty == false {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("REFERENCES").font(.caption).foregroundStyle(.secondary)
                        ForEach(item.references, id: \.self) { reference in
                            Text(reference).textSelection(.enabled)
                        }
                    }
                }
                HStack {
                    Text(item.capturedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Finish") { Task { await model.finishFocus(item.intentionID) } }
                    Button("Resume") { Task { await model.resumeFocus(item.intentionID) } }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func packetField(
        _ label: String,
        _ value: String,
        prominent: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(prominent ? .title3 : .body)
                .textSelection(.enabled)
        }
    }
}

private enum ElapsedCue {
    static func text(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainingSeconds = total % 60
        if hours > 0 { return "Focused for \(hours)h \(minutes)m" }
        if minutes > 0 { return "Focused for \(minutes)m \(remainingSeconds)s" }
        return "Focused for \(remainingSeconds)s"
    }
}

@MainActor
final class MainWindowController {
    private let window: NSWindow
    private let model: AppModel
    private let hostingController: NSHostingController<MainView>
    private(set) var selectedTabForTesting = 0

    init(model: AppModel) {
        self.model = model
        hostingController = NSHostingController(rootView: MainView(model: model))
        window = NSWindow(contentViewController: hostingController)
        window.title = "OpenLoop ADHD"
        window.setContentSize(NSSize(
            width: model.isAdvancedModeEnabled ? 1240 : 980,
            height: 720
        ))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarSeparatorStyle = .none
    }

    func show(tab: Int) {
        let selectedTab = WorkspaceOrientation.destinations.indices.contains(tab) ? tab : 0
        selectedTabForTesting = selectedTab
        hostingController.rootView = MainView(model: model, selection: selectedTab)
        if selectedTab == 1 || selectedTab == 3 { Task { await model.refreshMemory() } }
        if selectedTab == 1 || selectedTab == 2 || selectedTab == 3 {
            Task { await model.refreshSemanticGraph() }
        }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    var isVisibleForTesting: Bool { window.isVisible }
    var windowNumberForTesting: Int { window.windowNumber }

    func closeForTesting() {
        window.close()
    }
}
