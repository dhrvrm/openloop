import ADHDCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum ContextPresentation: String, CaseIterable {
    case list = "List"
    case space = "Space"
}

private struct MainView: View {
    @ObservedObject var model: AppModel
    @State var selection: WorkspaceDestination.ID = .now
    @State private var interruptionItem: NowItem?
    @State private var memoryHistoryExpanded = false
    @State private var quickAddText = ""
    @State private var privacyExpanded = false
    @State private var confirmingReset = false
    @State private var actSection = 0
    @State private var contextPresentation = ContextPresentation.space
    @State private var quickFindPresented = false
    @State private var sidebarVisible = true
    @FocusState private var recallFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            OpenLoopVisualSystem.canvas.ignoresSafeArea()
            HStack(spacing: 0) {
                if sidebarVisible {
                    workspaceSidebar
                    Divider().opacity(0.55)
                } else {
                    Button {
                        sidebarVisible = true
                    } label: {
                        Image(systemName: "sidebar.left")
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .help("Show sidebar · ⌘/")
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                selectedSurface
                    .frame(maxWidth: OpenLoopVisualSystem.contentMaximumWidth, alignment: .topLeading)
                    .padding(.horizontal, OpenLoopVisualSystem.contentHorizontalPadding)
                    .padding(.top, OpenLoopVisualSystem.contentTopPadding)
                    .padding(.bottom, OpenLoopVisualSystem.contentBottomPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(minWidth: sidebarVisible ? 760 : 520, minHeight: 560)
        .tint(OpenLoopVisualSystem.accent)
        .preferredColorScheme(preferredColorScheme)
        .inspector(
            isPresented: Binding(
                get: { model.isAdvancedModeEnabled },
                set: { model.setAdvancedModeEnabled($0) }
            )
        ) {
            AdvancedInspector(
                model: model,
                selectedDestination: WorkspaceOrientation.destination(selection)
            )
            .inspectorColumnWidth(
                min: 310,
                ideal: OpenLoopVisualSystem.inspectorIdealWidth,
                max: 410
            )
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.88),
            value: model.isAdvancedModeEnabled
        )
        .task { await model.refresh() }
        .onChange(of: selection) { _, tab in
            if tab == .ask {
                recallFieldFocused = true
            }
            if tab == .context { Task { await model.refreshMemory() } }
            if tab == .context || tab == .emerging || tab == .ask {
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
        .sheet(isPresented: $quickFindPresented) {
            QuickFindView(
                model: model,
                selection: $selection,
                isPresented: $quickFindPresented
            )
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
        case .context: contextView
        case .emerging: emergingView
        case .ask: askView
        case .act: actView
        case .inbox: inboxView
        case .later: laterView
        case .return: returnView
        case .transcripts: transcriptsView
        case .upcoming: scheduledTaskView(
            destination: .upcoming,
            eyebrow: "Plan",
            title: "Upcoming",
            detail: "Work you have deliberately scheduled for later."
        )
        case .someday: scheduledTaskView(
            destination: .someday,
            eyebrow: "Possibilities",
            title: "Someday",
            detail: "Ideas worth keeping without making them urgent."
        )
        case .now: nowView
        }
    }

    private var workspaceSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: OpenLoopVisualSystem.space5)
            VStack(alignment: .leading, spacing: OpenLoopVisualSystem.space4) {
                ForEach(WorkspaceOrientation.sections) { section in
                    VStack(alignment: .leading, spacing: 1) {
                        if section.id != .focus {
                            Text(section.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(OpenLoopVisualSystem.tertiaryText)
                                .padding(.horizontal, OpenLoopVisualSystem.space2)
                                .padding(.bottom, OpenLoopVisualSystem.space1)
                        }
                        ForEach(section.destinations) { destination in
                            WorkspaceSidebarButton(
                                destinationID: destination.id,
                                title: destination.title,
                                icon: destination.icon,
                                count: sidebarCount(for: destination.id),
                                isSelected: selection == destination.id
                            ) { selection = destination.id }
                            .dropDestination(for: String.self) { values, _ in
                                guard let value = values.first,
                                      let sourceID = UUID(uuidString: value),
                                      let target = intentionDestination(for: destination.id)
                                else { return false }
                                Task { await model.moveOpenLoop(sourceID, to: target) }
                                return true
                            }
                        }
                    }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    quickFindPresented = true
                } label: {
                    Label("Quick Find", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, OpenLoopVisualSystem.space2)
                        .frame(height: OpenLoopVisualSystem.compactRowMinimumHeight)
                }
                .buttonStyle(OpenLoopNavigationButtonStyle())
                .keyboardShortcut("f", modifiers: .command)
                .help("Travel to any list or task · ⌘F")

                Button {
                    sidebarVisible.toggle()
                } label: {
                    Label("Hide sidebar", systemImage: "sidebar.left")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, OpenLoopVisualSystem.space2)
                        .frame(height: OpenLoopVisualSystem.compactRowMinimumHeight)
                }
                .buttonStyle(OpenLoopNavigationButtonStyle())
                .keyboardShortcut("/", modifiers: .command)
                .help("Hide sidebar · ⌘/")

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
                    HStack(spacing: OpenLoopVisualSystem.space2) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 13, weight: .medium))
                        Text("Appearance")
                        Spacer()
                        Text(model.appearanceMode.displayName)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, OpenLoopVisualSystem.space2)
                    .frame(height: OpenLoopVisualSystem.compactRowMinimumHeight)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .font(OpenLoopVisualSystem.sidebarLabel)

                Divider().opacity(0.65)
                Button {
                    model.setAdvancedModeEnabled(!model.isAdvancedModeEnabled)
                } label: {
                    HStack(spacing: OpenLoopVisualSystem.space2) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .medium))
                        Text("Advanced")
                        Spacer()
                        Circle()
                            .fill(model.isAdvancedModeEnabled
                                ? OpenLoopVisualSystem.accent
                                : Color.secondary.opacity(0.35))
                            .frame(width: 6, height: 6)
                    }
                    .padding(.horizontal, OpenLoopVisualSystem.space2)
                    .frame(height: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(OpenLoopNavigationButtonStyle())
                .font(OpenLoopVisualSystem.sidebarLabel)
                .foregroundStyle(model.isAdvancedModeEnabled ? OpenLoopVisualSystem.accent : .secondary)
                .help("Show system details · ⌥⌘I")
                .accessibilityValue(model.isAdvancedModeEnabled ? "Shown" : "Hidden")
            }
        }
        .padding(.horizontal, OpenLoopVisualSystem.space2)
        .frame(width: OpenLoopVisualSystem.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(OpenLoopVisualSystem.sidebar)
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.appearanceMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private func sidebarCount(for destination: WorkspaceDestination.ID) -> Int? {
        let count = switch destination {
        case .now: model.openLoops.filter {
            $0.state == .open && $0.destination == .anytime
        }.count
        case .upcoming: model.openLoops.filter { $0.destination == .upcoming }.count
        case .someday: model.openLoops.filter { $0.destination == .someday }.count
        case .inbox: model.reviewItems.filter(\.needsDecision).count
        case .later: model.reviewItems.filter { !$0.needsDecision }.count
        case .return: model.returns.count
        case .transcripts: model.meetingTranscripts.count
        case .context: model.semanticNodes.count
        case .emerging: model.emergingThreads.count + model.unresolvedSemanticNodes.count
        case .act: model.openLoops.count + model.returns.count
        case .ask: 0
        }
        return count == 0 ? nil : count
    }

    private func intentionDestination(
        for workspace: WorkspaceDestination.ID
    ) -> IntentionDestination? {
        switch workspace {
        case .now: .anytime
        case .upcoming: .upcoming
        case .someday: .someday
        default: nil
        }
    }

    private var interruptionPresented: Binding<Bool> {
        Binding(
            get: { interruptionItem != nil },
            set: { if $0 == false { interruptionItem = nil } }
        )
    }

    private var nowView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    eyebrow: "Focus",
                    title: "Now",
                    detail: "Pick one thing to do now. Everything else stays saved."
                )

                if let notice = model.recoveryNotice {
                    StatusBanner(text: notice, icon: "checkmark.shield")
                }

                QuickAddComposer(model: model, text: $quickAddText) {
                    let captured = await model.submitCapture(quickAddText)
                    if captured { quickAddText = "" }
                }
                if model.isDeliveringDictation
                    || model.lastDictationDelivery != nil
                    || model.dictationActionNotice != nil {
                    DictationDeliveryPanel(model: model)
                }
                if model.meetingJob.stage != nil {
                    MeetingJobPanel(model: model)
                }
                CaptureCapabilityNote(summary: model.capabilitySummary)

                if let item = model.now, item.focus != nil {
                    currentIntention(item)
                } else if model.openLoops.contains(where: {
                    $0.state == .open && $0.destination == .anytime
                }) {
                    readyQueue
                } else if model.suggestions.isEmpty {
                    ContentUnavailableView(
                        model.returns.isEmpty ? "Nothing to do now" : "You can pick up where you stopped",
                        systemImage: model.returns.isEmpty
                            ? "circle.dashed"
                            : "arrow.uturn.backward.circle",
                        description: Text(
                            model.returns.isEmpty
                                ? WorkspaceOrientation.emptyCaptureGuidance
                                : "Open Return when you want to continue."
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                }

                if model.now?.focus != nil { contextTrailPanel }

                if model.suggestions.isEmpty == false {
                    VStack(alignment: .leading, spacing: 5) {
                        OpenLoopSectionHeading(title: "Relevant here")
                        Text("Related work you may want to continue.")
                            .font(OpenLoopVisualSystem.metadata)
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
            OpenLoopSectionHeading(
                title: "Next",
                detail: "Drag to reorder. Start only what deserves your attention now."
            )
            .padding(.bottom, OpenLoopVisualSystem.space1)

            ForEach(model.openLoops.filter {
                $0.state == .open && $0.destination == .anytime
            }) { item in
                ReadyTaskRow(model: model, item: item)
                Divider()
                    .padding(.leading, OpenLoopVisualSystem.checkboxHitSize + OpenLoopVisualSystem.space2)
            }
        }
        .frame(maxWidth: OpenLoopVisualSystem.contentMaximumWidth, alignment: .leading)
    }

    private func scheduledTaskView(
        destination: IntentionDestination,
        eyebrow: String,
        title: String,
        detail: String
    ) -> some View {
        let items = model.openLoops.filter {
            $0.state == .open && $0.destination == destination
        }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: OpenLoopVisualSystem.space5) {
                ScreenHeader(eyebrow: eyebrow, title: title, detail: detail)
                if items.isEmpty {
                    ContentUnavailableView(
                        "Nothing here",
                        systemImage: destination == .upcoming ? "calendar" : "archivebox",
                        description: Text("Move a task here from its ••• menu or drag it onto the sidebar.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            ReadyTaskRow(model: model, item: item)
                            Divider()
                                .padding(.leading, OpenLoopVisualSystem.checkboxHitSize + OpenLoopVisualSystem.space2)
                        }
                    }
                }
                if model.lastIntentionMove != nil {
                    Button("Undo last move") { Task { await model.undoLastIntentionMove() } }
                        .buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func currentIntention(_ item: NowItem) -> some View {
        VStack(alignment: .leading, spacing: OpenLoopVisualSystem.space3) {
            OpenLoopSectionHeading(title: "In focus")
            HStack(alignment: .top, spacing: OpenLoopVisualSystem.space2) {
                OpenLoopCheckbox(isCompleted: false, tint: OpenLoopVisualSystem.accent) {
                    Task { await model.finishFocus(item.intentionID) }
                }
                VStack(alignment: .leading, spacing: OpenLoopVisualSystem.space1) {
                    Text(item.desiredOutcome)
                        .font(OpenLoopVisualSystem.projectTitle)
                        .tracking(-0.5)
                    Text(item.nextAction)
                        .font(OpenLoopVisualSystem.rowTitle)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            if item.focus != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(ElapsedCue.text(seconds: item.elapsed(at: context.date)))
                        .font(OpenLoopVisualSystem.metadata.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.leading, OpenLoopVisualSystem.checkboxHitSize + OpenLoopVisualSystem.space2)
                }
            }
            focusControls(item)
                .padding(.leading, OpenLoopVisualSystem.checkboxHitSize + OpenLoopVisualSystem.space2)
        }
        .frame(maxWidth: OpenLoopVisualSystem.contentMaximumWidth, alignment: .leading)
    }

    private var contextTrailPanel: some View {
        VStack(alignment: .leading, spacing: OpenLoopVisualSystem.space3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: OpenLoopVisualSystem.space1) {
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
        .padding(.vertical, OpenLoopVisualSystem.space1)
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
                LazyHStack(spacing: OpenLoopVisualSystem.space2) {
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
                .padding(.vertical, OpenLoopVisualSystem.space1)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private func focusControls(_ item: NowItem) -> some View {
        HStack(spacing: 0) {
            if let focus = item.focus {
                if focus.state == .active {
                    Button("Pause") { Task { await model.pauseFocus(item.intentionID) } }
                        .buttonStyle(OpenLoopAccessoryButtonStyle(tint: .secondary))
                } else if focus.state == .paused {
                    Button("Continue") { Task { await model.continueFocus(item.intentionID) } }
                        .buttonStyle(OpenLoopAccessoryButtonStyle())
                }
                Button("Interrupt") { interruptionItem = item }
                    .buttonStyle(OpenLoopAccessoryButtonStyle(tint: .secondary))
                Button("Finish") { Task { await model.finishFocus(item.intentionID) } }
                    .buttonStyle(OpenLoopAccessoryButtonStyle())
            } else {
                Button("Start focus") { Task { await model.startFocus(item.intentionID) } }
                    .buttonStyle(OpenLoopAccessoryButtonStyle())
            }
        }
    }

    private var returnView: some View {
        VStack(alignment: .leading, spacing: OpenLoopVisualSystem.space3) {
            ScreenHeader(
                eyebrow: "RECOVERY",
                title: "Return",
                detail: "Pick up where you stopped, with the details you need."
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
                    LazyVStack(spacing: OpenLoopVisualSystem.space3) {
                        ForEach(model.returns) { item in
                            ReturnPacketView(model: model, item: item)
                        }
                    }
                }
            }
        }
    }

    private var inboxView: some View {
        let needsDecision = model.reviewItems.filter(\.needsDecision)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    eyebrow: "Capture",
                    title: "Inbox",
                    detail: "New notes and recordings wait here until you decide where they belong."
                )
                QuickAddComposer(model: model, text: $quickAddText) {
                    let captured = await model.submitCapture(quickAddText)
                    if captured { quickAddText = "" }
                }
                if needsDecision.isEmpty {
                    ContentUnavailableView(
                        "Inbox is clear",
                        systemImage: "tray",
                        description: Text("New notes and recordings appear here first.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    reviewSection(
                        title: "Needs a decision",
                        detail: "You choose what to do with each item.",
                        items: needsDecision
                    )
                }
            }
            .frame(maxWidth: OpenLoopVisualSystem.contentMaximumWidth, alignment: .leading)
            .padding(.bottom, OpenLoopVisualSystem.space4)
        }
    }

    private var laterView: some View {
        let heldSafely = model.reviewItems.filter { $0.needsDecision == false }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    eyebrow: "Focus",
                    title: "Later",
                    detail: "Things you saved but are not doing now."
                )

                if let error = model.reviewError {
                    Label(error, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if heldSafely.isEmpty {
                ContentUnavailableView(
                    "Nothing waiting",
                    systemImage: "archivebox",
                        description: Text("Move work here when it matters, but not right now.")
                )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    reviewSection(
                        title: "Held safely",
                        detail: "Edit these here or move one to Now.",
                        items: heldSafely
                    )
                }
            }
            .frame(maxWidth: OpenLoopVisualSystem.contentMaximumWidth, alignment: .leading)
            .padding(.bottom, OpenLoopVisualSystem.space4)
        }
    }

    private func reviewSection(
        title: String,
        detail: String,
        items: [ClarificationReviewItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OpenLoopSectionHeading(title: title, detail: detail)
                .padding(.bottom, OpenLoopVisualSystem.space2)

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
                LazyVStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    eyebrow: "QUERY",
                    title: "Ask your context",
                    detail: "Search your notes and recordings. Open a result to see where it came from."
                )

                semanticAskPanel

                meetingTranscriptSection { evidenceID in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(evidenceID, anchor: .center)
                    }
                }
                workingMemorySection
                privacySection

                HStack(spacing: OpenLoopVisualSystem.space2) {
                    TextField("Search captures, decisions, return points, and corrections", text: $model.recallQuery)
                        .openLoopTextField()
                        .font(OpenLoopVisualSystem.rowTitle)
                        .focused($recallFieldFocused)
                        .onSubmit { Task { await model.searchRecall(model.recallQuery) } }
                    Button("Search") {
                        Task { await model.searchRecall(model.recallQuery) }
                    }
                    .buttonStyle(OpenLoopAccessoryButtonStyle())
                    .disabled(model.recallQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack {
                    Text("⌘⇧F opens Ask")
                    Spacer()
                    Text("Searches only this Mac")
                }
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)

                if model.isRecalling {
                    ProgressView("Searching on this Mac…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let error = model.recallError {
                    ContentUnavailableView(
                        "Search is unavailable",
                        systemImage: "magnifyingglass",
                        description: Text(error)
                    )
                } else if model.recallQuery.isEmpty {
                    ContentUnavailableView(
                        "Search what you saved",
                        systemImage: "text.magnifyingglass",
                        description: Text("Try a name, exact phrase, decision, or restart action.")
                    )
                } else if model.recallHits.isEmpty {
                    ContentUnavailableView(
                        "No match found",
                        systemImage: "magnifyingglass",
                        description: Text("Try a name, phrase, or different words.")
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.recallHits) { hit in
                            RecallEvidenceRow(hit: hit)
                            Divider()
                        }
                    }
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, OpenLoopVisualSystem.space4)
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

    private var transcriptsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ScreenHeader(
                        eyebrow: "VOICE EVIDENCE",
                        title: "Transcripts",
                        detail: "Recordings, exact words, summaries, decisions, and possible next steps stay together."
                    )
                    meetingTranscriptSection { evidenceID in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(evidenceID, anchor: .center)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, OpenLoopVisualSystem.space4)
            }
        }
    }

    private var semanticAskPanel: some View {
        VStack(alignment: .leading, spacing: OpenLoopVisualSystem.space3) {
            OpenLoopSectionHeading(
                title: "Ask a question",
                tint: OpenLoopVisualSystem.ask,
                detail: "Answers use your saved notes and recordings"
            )
            HStack(spacing: OpenLoopVisualSystem.space2) {
                TextField("What have I been thinking about?", text: $model.semanticQuery)
                    .openLoopTextField()
                    .onSubmit { Task { await model.askSemanticContext(model.semanticQuery) } }
                Button("Ask locally") {
                    Task { await model.askSemanticContext(model.semanticQuery) }
                }
                .buttonStyle(OpenLoopAccessoryButtonStyle(tint: OpenLoopVisualSystem.ask))
                .disabled(model.semanticQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error = model.semanticError {
                Label(error, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if model.semanticQuery.isEmpty {
                Text("OpenLoop searches this Mac and shows the source of each answer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if model.semanticAnswers.isEmpty {
                Text("No answer found in what you saved.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.semanticAnswers) { answer in
                    VStack(alignment: .leading, spacing: OpenLoopVisualSystem.space1) {
                        SemanticNodeRow(node: answer.node, showEvidence: true)
                        HStack(spacing: OpenLoopVisualSystem.space2) {
                            if !answer.related.isEmpty {
                                Text("\(answer.related.count) connected")
                            }
                            if answer.history.contains(where: { event in
                                if case .supersession = event { return true }
                                return false
                            }) {
                                Text("Belief updated")
                            }
                            if model.isAdvancedModeEnabled {
                                Text("\(Int((answer.relevance * 100).rounded()))% relevance")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, OpenLoopVisualSystem.space1)
    }

    private var contextView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    eyebrow: "Understanding",
                    title: "Context",
                    detail: "See the people, projects, questions, and decisions connected to your notes."
                )
                Picker("Context presentation", selection: $contextPresentation) {
                    ForEach(ContextPresentation.allCases, id: \.self) { presentation in
                        Text(presentation.rawValue).tag(presentation)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 168)
                if model.isRefreshingSemanticGraph {
                    ProgressView("Updating connections…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let error = model.semanticError {
                    ContentUnavailableView(
                        "Connections are unavailable",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text(error)
                    )
                } else if model.semanticNodes.isEmpty {
                    ContentUnavailableView(
                        "No connections yet",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Add a note or recording. Connections appear when OpenLoop finds clear links.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    if contextPresentation == .space {
                        SemanticGraph3DView(
                            nodes: model.semanticNodes,
                            relations: model.semanticRelations,
                            vectors: model.semanticVectors
                        )
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(model.semanticNodes) { node in
                                SemanticNodeRow(node: node, showEvidence: true)
                                Divider()
                            }
                        }
                        .padding(.horizontal, OpenLoopVisualSystem.space2)
                    }
                }
                workingMemorySection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, OpenLoopVisualSystem.space4)
        }
        .task {
            await model.refreshSemanticGraph()
            await model.refreshMemory()
        }
    }

    private var emergingView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    eyebrow: "PATTERNS",
                    title: "Emerging",
                    detail: "See topics and open questions that keep coming up. Nothing becomes a task unless you choose it."
                )
                if model.emergingThreads.isEmpty && model.unresolvedSemanticNodes.isEmpty {
                    ContentUnavailableView(
                        "No repeated topics yet",
                        systemImage: "sparkles",
                        description: Text("A topic appears here after it comes up more than once.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    if !model.unresolvedSemanticNodes.isEmpty {
                        SemanticSectionTitle(
                            title: "Unresolved",
                            detail: "Questions and problems that still need an answer."
                        )
                        ForEach(model.unresolvedSemanticNodes) { node in
                            SemanticNodeRow(node: node, showEvidence: true)
                        }
                    }
                    if !model.emergingThreads.isEmpty {
                        SemanticSectionTitle(
                            title: "Threads",
                            detail: "Ideas that appear together in your notes and recordings."
                        )
                        ForEach(model.emergingThreads) { thread in
                            SemanticThreadRow(thread: thread)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, OpenLoopVisualSystem.space4)
        }
        .task { await model.refreshSemanticGraph() }
    }

    private var actView: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(
                eyebrow: "EXECUTION",
                title: "Act",
                detail: "Choose what to do next. OpenLoop never acts without your approval."
            )
            Picker("Action workspace", selection: $actSection) {
                Text("Ready").tag(0)
                Text("Return").tag(1)
                Text("Review").tag(2)
                Text("Tools").tag(3)
            }
            .pickerStyle(.segmented)

            switch actSection {
            case 1: returnView
            case 2: laterView
            case 3: capabilityRuntimeView
            default:
                if let item = model.now, item.focus != nil {
                    currentIntention(item)
                } else if model.openLoops.contains(where: { $0.state == .open }) {
                    readyQueue
                } else {
                    ContentUnavailableView(
                        "Nothing ready to act on",
                        systemImage: "bolt.circle",
                        description: Text("Possible next steps stay in Emerging until you choose one.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var capabilityRuntimeView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OpenLoopVisualSystem.space5) {
                if !model.toolCapabilities.isEmpty {
                    VStack(alignment: .leading, spacing: OpenLoopVisualSystem.space2) {
                        OpenLoopSectionHeading(
                            title: "Ask a connected tool",
                            detail: "OpenLoop shows the route before anything can change"
                        )
                        TextField(
                            "For example: create a GitHub issue for the release bug",
                            text: $model.toolActionIntent
                        )
                        .openLoopTextField()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Values · one key=value per line")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $model.toolActionParameters)
                                .font(.system(.callout, design: .monospaced))
                                .frame(minHeight: 58, maxHeight: 96)
                                .padding(6)
                                .background(
                                    OpenLoopVisualSystem.raised,
                                    in: RoundedRectangle(cornerRadius: OpenLoopVisualSystem.inputRadius)
                                )
                        }
                        HStack {
                            Button("Prepare") {
                                Task { await model.prepareToolAction() }
                            }
                            .buttonStyle(OpenLoopAccessoryButtonStyle(tint: OpenLoopVisualSystem.accent))
                            .disabled(model.toolActionIntent.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty || model.isRunningToolAction)
                            if let result = model.toolActionResult {
                                Label(result, systemImage: "checkmark.circle.fill")
                                    .font(.callout)
                                    .foregroundStyle(OpenLoopVisualSystem.later)
                                    .lineLimit(2)
                            }
                        }
                        if let action = model.preparedToolAction {
                            VStack(alignment: .leading, spacing: OpenLoopVisualSystem.space1) {
                                Label(
                                    action.route.capability.tool.replacingOccurrences(
                                        of: "_",
                                        with: " "
                                    ),
                                    systemImage: action.route.requiresConfirmation
                                        ? "exclamationmark.shield"
                                        : "eye"
                                )
                                .font(OpenLoopVisualSystem.rowTitleEmphasized)
                                Text(action.route.requiresConfirmation
                                    ? "This will change data through \(action.route.capability.server). Review the values, then confirm."
                                    : "This reads through \(action.route.capability.server). It will not change data.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Button(action.route.requiresConfirmation ? "Confirm and run" : "Run") {
                                        Task { await model.executePreparedToolAction() }
                                    }
                                    .buttonStyle(OpenLoopAccessoryButtonStyle(
                                        tint: action.route.requiresConfirmation
                                            ? OpenLoopVisualSystem.recording
                                            : OpenLoopVisualSystem.accent
                                    ))
                                    .disabled(model.isRunningToolAction)
                                    Button("Cancel") {
                                        Task { await model.cancelPreparedToolAction() }
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(OpenLoopVisualSystem.space2)
                            .background(
                                OpenLoopVisualSystem.accentSoft,
                                in: RoundedRectangle(cornerRadius: OpenLoopVisualSystem.editorRadius)
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: OpenLoopVisualSystem.space1) {
                    OpenLoopSectionHeading(
                        title: "Connected tools",
                        detail: "New tools start at Observe. Suggest and Act always require your choice."
                    )
                    if model.toolCapabilities.isEmpty {
                        ContentUnavailableView(
                            "No tools connected",
                            systemImage: "puzzlepiece.extension",
                            description: Text(
                                "When an MCP tool is discovered, it appears here before OpenLoop can route anything to it."
                            )
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        ForEach(model.toolCapabilities) { capability in
                            HStack(spacing: OpenLoopVisualSystem.space3) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(capability.server)
                                        .font(OpenLoopVisualSystem.rowTitleEmphasized)
                                    Text(capability.tool.replacingOccurrences(of: "_", with: " "))
                                        .font(OpenLoopVisualSystem.metadata)
                                        .foregroundStyle(.secondary)
                                    Text(capability.risk == .readOnly
                                        ? "Read only"
                                        : capability.risk == .reversibleWrite
                                            ? "Can change data · confirmation required"
                                            : "Destructive · confirmation always required")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Picker(
                                    "Permission",
                                    selection: Binding(
                                        get: { capability.grantedPermission },
                                        set: { permission in
                                            Task {
                                                await model.grantCapability(
                                                    permission,
                                                    capabilityID: capability.id
                                                )
                                            }
                                        }
                                    )
                                ) {
                                    Text("Observe").tag(CapabilityPermission.observe)
                                    Text("Suggest").tag(CapabilityPermission.suggest)
                                    Text("Act").tag(CapabilityPermission.act)
                                }
                                .frame(width: 130)
                            }
                            .padding(.vertical, OpenLoopVisualSystem.space2)
                            Divider()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: OpenLoopVisualSystem.space2) {
                    OpenLoopSectionHeading(
                        title: "Action history",
                        detail: "Proposals, confirmations, results, failures, and cancellations"
                    )
                    if model.toolActionAudit.isEmpty {
                        Text("No tool action has been proposed or run.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.toolActionAudit.prefix(30)) { record in
                            HStack(alignment: .top, spacing: OpenLoopVisualSystem.space2) {
                                Image(systemName: actionStatusIcon(record.status))
                                    .foregroundStyle(actionStatusTint(record.status))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.intent)
                                        .font(OpenLoopVisualSystem.rowTitle)
                                    Text("\(record.capabilityID) · \(record.status.rawValue)")
                                        .font(OpenLoopVisualSystem.metadata)
                                        .foregroundStyle(.secondary)
                                    if let message = record.message {
                                        Text(message)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                Text(record.occurredAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, OpenLoopVisualSystem.space1)
                        }
                    }
                }
                if let error = model.capabilityRuntimeError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await model.refreshCapabilityRuntime() }
    }

    private func actionStatusIcon(_ status: ToolActionStatus) -> String {
        switch status {
        case .proposed: "doc.badge.ellipsis"
        case .confirmed: "checkmark.circle"
        case .executing: "gearshape.2"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private func actionStatusTint(_ status: ToolActionStatus) -> Color {
        switch status {
        case .succeeded: OpenLoopVisualSystem.later
        case .failed: OpenLoopVisualSystem.recording
        case .executing: OpenLoopVisualSystem.accent
        default: OpenLoopVisualSystem.muted
        }
    }

    @ViewBuilder private func meetingTranscriptSection(
        onEvidence: @escaping (UUID) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                OpenLoopSectionHeading(
                    title: "Meeting transcripts",
                    tint: OpenLoopVisualSystem.inbox,
                    detail: model.meetingTranscripts.isEmpty
                        ? "High-accuracy models · runs on this Mac"
                        : "\(model.meetingTranscripts.count) stored locally"
                )
                Button("Import audio…") { presentMeetingImporter() }
                    .buttonStyle(OpenLoopAccessoryButtonStyle(tint: OpenLoopVisualSystem.inbox))
            }

            if model.meetingJob.stage != nil {
                MeetingJobPanel(model: model)
            }

            if model.meetingTranscripts.isEmpty && model.meetingJob.stage == nil {
                Text("Choose a meeting recording. The first run downloads the speech model. Your audio stays on this Mac.")
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
        .padding(.vertical, 4)
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
                    PrivacyMetric(value: "\(model.privacySummary.captureCount)", label: "Captures")
                    PrivacyMetric(value: "\(model.privacySummary.openIntentionCount)", label: "Open")
                    PrivacyMetric(value: "\(model.privacySummary.memoryCount)", label: "Memories")
                    PrivacyMetric(
                        value: ByteCountFormatter.string(
                            fromByteCount: model.privacySummary.encryptedBytes,
                            countStyle: .file
                        ),
                        label: "Encrypted"
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
        .padding(.vertical, 8)
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
                        OpenLoopSectionHeading(
                            title: "Saved facts",
                            tint: OpenLoopVisualSystem.context,
                            detail: "Things OpenLoop remembers, with the note or recording they came from"
                        )
                    }
                    Spacer()
                    Button("Refresh evidence") {
                        Task { await model.refreshMemory() }
                    }
                    .buttonStyle(.link)
                    .disabled(model.isCompilingMemory)
                }

                if model.isCompilingMemory && model.memoryRecords.isEmpty {
                    ProgressView("Checking saved facts…")
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
        let tint = OpenLoopVisualSystem.tint(forSurfaceTitle: title)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: OpenLoopVisualSystem.space2) {
                Image(systemName: OpenLoopVisualSystem.icon(forSurfaceTitle: title))
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 27)
                Text(title)
                    .font(OpenLoopVisualSystem.listTitle)
                    .tracking(-0.8)
            }
            Text(detail)
                .font(.system(size: 12.5))
                .foregroundStyle(OpenLoopVisualSystem.muted)
                .frame(maxWidth: 560, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(eyebrow), \(title). \(detail)")
    }
}

private struct WorkspaceSidebarButton: View {
    let destinationID: WorkspaceDestination.ID
    let title: String
    let icon: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let tint = OpenLoopVisualSystem.tint(for: destinationID)
        Button(action: action) {
            HStack(spacing: OpenLoopVisualSystem.space2) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 17)
                    .foregroundStyle(tint.opacity(isSelected ? 1 : 0.78))
                Text(title)
                    .font(isSelected
                        ? OpenLoopVisualSystem.sidebarLabelSelected
                        : OpenLoopVisualSystem.sidebarLabel)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(OpenLoopVisualSystem.muted)
                }
            }
            .padding(.horizontal, OpenLoopVisualSystem.space2)
            .frame(minHeight: OpenLoopVisualSystem.compactRowMinimumHeight)
            .contentShape(Rectangle())
            .background(
                isSelected
                    ? OpenLoopVisualSystem.selection
                    : (isHovered ? OpenLoopVisualSystem.selectionInactive : Color.clear),
                in: RoundedRectangle(
                    cornerRadius: OpenLoopVisualSystem.sidebarSelectionRadius,
                    style: .continuous
                )
            )
        }
        .buttonStyle(OpenLoopNavigationButtonStyle())
        .onHover { hovered in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovered }
        }
    }
}

private struct QuickFindView: View {
    @ObservedObject var model: AppModel
    @Binding var selection: WorkspaceDestination.ID
    @Binding var isPresented: Bool
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var destinations: [WorkspaceDestination] {
        guard !normalizedQuery.isEmpty else { return WorkspaceOrientation.destinations }
        return WorkspaceOrientation.destinations.filter {
            $0.title.lowercased().contains(normalizedQuery)
        }
    }

    private var tasks: [OpenLoopItem] {
        guard !normalizedQuery.isEmpty else { return [] }
        return model.openLoops.filter {
            $0.desiredOutcome.lowercased().contains(normalizedQuery)
                || $0.nextAction.lowercased().contains(normalizedQuery)
                || $0.tags.contains { $0.lowercased().contains(normalizedQuery) }
        }.prefix(8).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: OpenLoopVisualSystem.space2) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find a list or task", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                Button("Done") { isPresented = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(OpenLoopVisualSystem.accent)
            }
            .padding(18)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !destinations.isEmpty {
                        quickFindHeading("Lists")
                        ForEach(destinations) { destination in
                            Button {
                                selection = destination.id
                                isPresented = false
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: destination.icon)
                                        .foregroundStyle(OpenLoopVisualSystem.tint(for: destination.id))
                                        .frame(width: 20)
                                    Text(destination.title)
                                    Spacer()
                                }
                                .padding(.horizontal, 18)
                                .frame(height: 38)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !tasks.isEmpty {
                        quickFindHeading("Tasks")
                        ForEach(tasks) { task in
                            Button {
                                selection = destination(for: task)
                                isPresented = false
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.desiredOutcome)
                                        .font(OpenLoopVisualSystem.rowTitle)
                                    Text(task.nextAction)
                                        .font(OpenLoopVisualSystem.metadata)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if destinations.isEmpty && tasks.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 540, height: 480)
        .background(OpenLoopVisualSystem.canvas)
        .task { searchFocused = true }
    }

    private func quickFindHeading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.7)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 5)
    }

    private func destination(for task: OpenLoopItem) -> WorkspaceDestination.ID {
        if task.state == .interrupted { return .return }
        switch task.destination {
        case .anytime: return .now
        case .upcoming: return .upcoming
        case .someday: return .someday
        }
    }
}

private struct QuickAddComposer: View {
    @ObservedObject var model: AppModel
    @Binding var text: String
    let submit: () async -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: OpenLoopVisualSystem.space2) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(OpenLoopVisualSystem.accent)
                    .frame(width: OpenLoopVisualSystem.checkboxHitSize)
                TextField("New thought, task, or note", text: $text)
                    .textFieldStyle(.plain)
                    .font(OpenLoopVisualSystem.rowTitle)
                    .focused($isTextFieldFocused)
                    .onSubmit { Task { await submit() } }
                Button {
                    Task { await submit() }
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.turn.down.left")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(OpenLoopAccessoryButtonStyle())
                .help("Capture · Return")
                .disabled(isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, OpenLoopVisualSystem.space3)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .background(
                isTextFieldFocused
                    ? OpenLoopVisualSystem.raised
                    : OpenLoopVisualSystem.selectionInactive.opacity(0.64),
                in: RoundedRectangle(
                    cornerRadius: OpenLoopVisualSystem.editorRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: OpenLoopVisualSystem.editorRadius,
                    style: .continuous
                )
                .stroke(
                    isTextFieldFocused ? OpenLoopVisualSystem.focusRing : .clear,
                    lineWidth: 1.5
                )
            }

            HStack(alignment: .center, spacing: 0) {
                Button {
                    model.toggleVoiceCapture()
                } label: {
                    Label(
                        model.meetingJob.stage == .recording ? "Stop & transcribe" : "Record",
                        systemImage: model.meetingJob.stage == .recording
                            ? "stop.fill"
                            : "record.circle.fill"
                    )
                }
                .buttonStyle(OpenLoopAccessoryButtonStyle(tint:
                    model.meetingJob.stage == .recording
                        ? OpenLoopVisualSystem.recording
                        : OpenLoopVisualSystem.recording.opacity(0.88)
                ))
                .help("Record and transcribe · ⌃⌥R")
                .disabled(
                    model.isSystemDictationActive
                        || (model.meetingJob.isActive && model.meetingJob.stage != .recording)
                )
                Button {
                    model.toggleSystemDictation()
                } label: {
                    Label(
                        model.isSystemDictationActive && model.meetingJob.stage == .recording
                            ? "Stop & insert"
                            : "Dictate",
                        systemImage: model.isSystemDictationActive && model.meetingJob.stage == .recording
                            ? "stop.fill"
                            : "waveform"
                    )
                }
                .buttonStyle(OpenLoopAccessoryButtonStyle(tint:
                    model.isSystemDictationActive
                        ? OpenLoopVisualSystem.recording
                        : OpenLoopVisualSystem.accent
                ))
                .help("Dictate into the active app · ⌃⌥Space")
                .disabled(
                    model.meetingJob.isActive
                        && !(model.isSystemDictationActive && model.meetingJob.stage == .recording)
                )
                Button("Import audio", systemImage: "waveform.badge.plus") {
                    presentMeetingImporter()
                }
                .buttonStyle(OpenLoopAccessoryButtonStyle(tint: .secondary))
                .disabled(model.meetingJob.isActive)
                Spacer(minLength: 8)
                Picker(
                    "Voice mode",
                    selection: Binding(
                        get: { model.voiceMode },
                        set: { model.setVoiceMode($0) }
                    )
                ) {
                    ForEach(VoiceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .help("Voice output style")
            }
            .padding(.top, OpenLoopVisualSystem.space1)
            .padding(.horizontal, OpenLoopVisualSystem.space1)
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
                    .font(OpenLoopVisualSystem.rowTitle)
                    .textSelection(.enabled)
                    .padding(.leading, OpenLoopVisualSystem.checkboxHitSize + OpenLoopVisualSystem.space2)
                    .padding(.vertical, OpenLoopVisualSystem.space2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Live transcription")
                }
            }
        }
        .padding(.vertical, OpenLoopVisualSystem.space2)
        .frame(maxWidth: OpenLoopVisualSystem.contentMaximumWidth, alignment: .leading)
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

private struct DictationDeliveryPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    panelTitle,
                    systemImage: model.isDeliveringDictation
                        ? "sparkles"
                        : "text.cursor"
                )
                .font(.callout.weight(.semibold))
                Spacer()
                Text(model.voiceMode.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OpenLoopVisualSystem.muted)
            }
            if model.isDeliveringDictation {
                ProgressView()
                    .controlSize(.small)
                Text(model.dictationProcessingMessage ?? "Processing locally")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let delivery = model.lastDictationDelivery {
                Text(delivery.statusMessage)
                    .font(.callout)
                    .foregroundStyle(delivery.state == .failed ? .orange : .secondary)
                HStack(spacing: 8) {
                    Text(delivery.processingRoute.displayName)
                    if let outputRoute = delivery.outputRoute {
                        Text("→")
                        Text(outputRoute.displayName)
                    }
                }
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                if delivery.rawText != delivery.processedText {
                    DisclosureGroup("Raw and processed text") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Raw input").font(OpenLoopVisualSystem.metadata.weight(.medium)).foregroundStyle(.secondary)
                            Text(delivery.rawText).textSelection(.enabled)
                            Text("Processed output").font(OpenLoopVisualSystem.metadata.weight(.medium)).foregroundStyle(.secondary)
                            Text(delivery.processedText).textSelection(.enabled)
                        }
                        .font(.caption)
                        .padding(.top, 6)
                    }
                }
                HStack(spacing: 9) {
                    if delivery.state == .awaitingConfirmation {
                        Button("Confirm \(delivery.command?.displayName ?? "command")") {
                            model.confirmPendingVoiceCommand()
                        }
                        .buttonStyle(OpenLoopAccessoryButtonStyle())
                        Button("Cancel") { model.discardPendingVoiceCommand() }
                    } else if delivery.state == .inserted, delivery.command != .undo {
                        Button("Undo output") { model.undoLastDictationOutput() }
                    }
                }
            } else if let notice = model.dictationActionNotice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .openLoopPanel(emphasized: model.isDeliveringDictation)
    }

    private var panelTitle: String {
        if model.isDeliveringDictation { return "Processing dictation" }
        if model.lastDictationDelivery?.state == .awaitingConfirmation {
            return "Confirm voice command"
        }
        return "Dictation output"
    }
}

private extension VoiceProcessingRoute {
    var displayName: String {
        switch self {
        case .direct: "Raw · deterministic"
        case .deterministicCommand: "Voice command"
        case .compactLocalEditor: "Local semantic edit"
        case .largeLocalEditor: "Deep local semantic edit"
        case .rawFallback: "Raw safety fallback"
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
                Text("Microphone")
                    .font(.system(size: 12, weight: .semibold))
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
            .animation(.spring(response: 0.12, dampingFraction: 0.82), value: decibels)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            OpenLoopVisualSystem.recording.opacity(0.045),
            in: RoundedRectangle(cornerRadius: OpenLoopVisualSystem.editorRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: OpenLoopVisualSystem.editorRadius, style: .continuous)
                .stroke(.red.opacity(0.20), lineWidth: 0.75)
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
        guard let decibels else { return "Listening" }
        if decibels < -45 { return "Signal low" }
        if decibels < -28 { return "Hearing you" }
        return "Strong signal"
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
                Text("Local only")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                if model.meetingJob.requestedLanguage != .automatic {
                    Text(model.meetingJob.requestedLanguage.title)
                        .font(.system(size: 12, weight: .medium))
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
                .background(.background.opacity(0.62), in: RoundedRectangle(cornerRadius: OpenLoopVisualSystem.inputRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: OpenLoopVisualSystem.inputRadius)
                        .stroke(OpenLoopVisualSystem.hairline, lineWidth: 0.75)
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
                        .buttonStyle(OpenLoopAccessoryButtonStyle())
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
            return "Recorded \(durationText) · peak \(Int(peak.rounded())) dB"
        }
        return "Recorded \(durationText) · no level data"
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

                    if let fusion = transcript.fusionEvidence,
                       !fusion.reviewSpans.isEmpty {
                        fusionReview(fusion)
                    }

                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            Text("Transcript")
                                .font(.headline)
                            Spacer()
                            Text("Evidence")
                                .font(.system(size: 12, weight: .medium))
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
                                        Text(speaker)
                                            .font(.system(size: 12, weight: .medium))
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
                    Text("\(duration(transcript.duration)) · \(transcript.detectedLanguage?.capitalized ?? "Auto detected") · \(transcript.createdAt.formatted(date: .abbreviated, time: .shortened))")
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
        .padding(.vertical, OpenLoopVisualSystem.space2)
        .openLoopInteractiveRow()
        .overlay(alignment: .bottom) { Divider() }
    }

    private func fusionReview(_ fusion: TranscriptFusionResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Check uncertain words", systemImage: "text.badge.checkmark")
                .font(.headline)
            Text("Two local recognizers heard these parts differently. The current wording is kept until you choose.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(fusion.reviewSpans) { span in
                VStack(alignment: .leading, spacing: 7) {
                    candidate("Current", span.selectedText)
                    if let secondary = span.secondary {
                        let alternative = span.selectedText == secondary.text
                            ? span.primary.text
                            : secondary.text
                        candidate("Alternative", alternative)
                        Button("Use alternative") {
                            Task {
                                _ = await model.correctMeetingSegment(
                                    transcriptID: transcript.id,
                                    segmentID: span.primary.id,
                                    correctedText: alternative
                                )
                            }
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(10)
                .background(
                    OpenLoopVisualSystem.accentSoft,
                    in: RoundedRectangle(cornerRadius: OpenLoopVisualSystem.inputRadius)
                )
            }
        }
    }

    private func candidate(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private var intelligence: MeetingIntelligence {
        model.meetingInterpretations[transcript.id]?.intelligence
            ?? MeetingIntelligenceCompiler().compile(transcript)
    }

    @ViewBuilder
    private func meetingBrief(onEvidence: @escaping (MeetingInsight) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Meeting notes", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(OpenLoopVisualSystem.accent)
                    Text("Based on the transcript. Runs on this Mac and does not create tasks for you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.meetingInterpretations[transcript.id].map {
                    "Saved · v\($0.schemaVersion)"
                } ?? "Local · extractive")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OpenLoopVisualSystem.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        OpenLoopVisualSystem.accentSoft,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
            }

            briefSection(
                title: "Summary",
                icon: "text.quote",
                insights: intelligence.summary,
                emptyText: "Not enough speech to form a useful summary.",
                onEvidence: onEvidence
            )

            briefSection(
                title: "Open questions",
                icon: "questionmark.bubble",
                insights: intelligence.questions,
                emptyText: MeetingIntelligencePresentation.emptyQuestionText,
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
                "Possible next steps stay here until you review them. OpenLoop does not add them to Now.",
                systemImage: "hand.raised"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            OpenLoopVisualSystem.accent.opacity(0.045),
            in: RoundedRectangle(cornerRadius: OpenLoopVisualSystem.editorRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: OpenLoopVisualSystem.editorRadius)
                .stroke(OpenLoopVisualSystem.accent.opacity(0.14), lineWidth: 0.75)
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
            .font(OpenLoopVisualSystem.metadata)
            .foregroundStyle(OpenLoopVisualSystem.accent)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReadyTaskRow: View {
    @ObservedObject var model: AppModel
    let item: OpenLoopItem
    @State private var isDropTarget = false
    @State private var isHovered = false
    @State private var isEditing = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            OpenLoopCheckbox(isCompleted: false) {
                Task { await model.finishOpenLoop(item.id) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    isEditing = true
                } label: {
                    Text(item.desiredOutcome)
                        .font(OpenLoopVisualSystem.rowTitle)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Text(item.nextAction)
                    .font(OpenLoopVisualSystem.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if item.heading != nil || !item.tags.isEmpty || item.scheduledAt != nil
                    || item.deadline != nil || !item.checklist.isEmpty {
                    TaskMetadataLine(item: item)
                }
            }
            Spacer(minLength: 14)
            Button {
                Task { await model.startFocus(item.id) }
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(OpenLoopAccessoryButtonStyle())
            .help("Start focus")
            .opacity(isHovered ? 1 : 0)
            Menu {
                Button("Open details") { isEditing = true }
                Divider()
                Button("Move up") { Task { await model.moveOpenLoop(item.id, by: -1) } }
                Button("Move down") { Task { await model.moveOpenLoop(item.id, by: 1) } }
                Divider()
                Menu("Move to") {
                    Button("Now") { Task { await model.moveOpenLoop(item.id, to: .anytime) } }
                    Button("Upcoming") { Task { await model.moveOpenLoop(item.id, to: .upcoming) } }
                    Button("Someday") { Task { await model.moveOpenLoop(item.id, to: .someday) } }
                }
                Divider()
                Button("Finish") { Task { await model.finishOpenLoop(item.id) } }
                Button("Release", role: .destructive) { Task { await model.releaseOpenLoop(item.id) } }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .opacity(isHovered ? 1 : 0.34)
        }
        .padding(.vertical, OpenLoopVisualSystem.space2)
        .padding(.horizontal, OpenLoopVisualSystem.space1)
        .frame(minHeight: OpenLoopVisualSystem.taskRowMinimumHeight)
        .contentShape(Rectangle())
        .background(
            isDropTarget
                ? OpenLoopVisualSystem.accentSoft
                : (isHovered ? OpenLoopVisualSystem.selectionInactive : Color.clear),
            in: RoundedRectangle(
                cornerRadius: OpenLoopVisualSystem.sidebarSelectionRadius,
                style: .continuous
            )
        )
        .draggable(item.id.uuidString) {
            Label(item.desiredOutcome, systemImage: "circle")
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        }
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first,
                  let sourceID = UUID(uuidString: value),
                  sourceID != item.id else { return false }
            Task { await model.moveOpenLoop(sourceID, before: item.id) }
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
        .onHover { hovered in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovered }
        }
        .accessibilityAction(named: "Move up") {
            Task { await model.moveOpenLoop(item.id, by: -1) }
        }
        .accessibilityAction(named: "Move down") {
            Task { await model.moveOpenLoop(item.id, by: 1) }
        }
        .accessibilityAction(named: "Open details") { isEditing = true }
        .sheet(isPresented: $isEditing) {
            TaskDetailEditor(model: model, item: item, isPresented: $isEditing)
        }
    }
}

private struct TaskMetadataLine: View {
    let item: OpenLoopItem

    var body: some View {
        HStack(spacing: 8) {
            if let heading = item.heading {
                Label(heading, systemImage: "textformat")
            }
            if let date = item.scheduledAt {
                Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
            }
            if let deadline = item.deadline {
                Label(deadline.formatted(date: .abbreviated, time: .omitted), systemImage: "flag")
            }
            if !item.checklist.isEmpty {
                let completed = item.checklist.filter(\.isCompleted).count
                Label("\(completed)/\(item.checklist.count)", systemImage: "checklist")
            }
            ForEach(item.tags.prefix(2), id: \.self) { tag in
                Text("#\(tag)")
            }
        }
        .font(.system(size: 11.5, weight: .regular))
        .foregroundStyle(OpenLoopVisualSystem.muted)
        .lineLimit(1)
    }
}

private struct TaskDetailEditor: View {
    @ObservedObject var model: AppModel
    let item: OpenLoopItem
    @Binding var isPresented: Bool
    @State private var heading: String
    @State private var hasScheduledDate: Bool
    @State private var scheduledAt: Date
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var tags: String
    @State private var checklist: [IntentionChecklistItem]
    @State private var newChecklistText = ""
    @State private var isSaving = false

    init(model: AppModel, item: OpenLoopItem, isPresented: Binding<Bool>) {
        self.model = model
        self.item = item
        _isPresented = isPresented
        _heading = State(initialValue: item.heading ?? "")
        _hasScheduledDate = State(initialValue: item.scheduledAt != nil)
        _scheduledAt = State(initialValue: item.scheduledAt ?? .now)
        _hasDeadline = State(initialValue: item.deadline != nil)
        _deadline = State(initialValue: item.deadline ?? .now)
        _tags = State(initialValue: item.tags.joined(separator: ", "))
        _checklist = State(initialValue: item.checklist)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.desiredOutcome)
                        .font(.system(size: 24, weight: .semibold))
                    Text(item.nextAction)
                        .font(OpenLoopVisualSystem.metadata)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 28)
                Button("Done") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
            .padding(.bottom, 28)

            Form {
                TextField("Heading", text: $heading)

                Toggle("Schedule", isOn: $hasScheduledDate)
                if hasScheduledDate {
                    DatePicker(
                        "Scheduled date",
                        selection: $scheduledAt,
                        displayedComponents: [.date]
                    )
                }

                Toggle("Deadline", isOn: $hasDeadline)
                if hasDeadline {
                    DatePicker("Deadline", selection: $deadline, displayedComponents: [.date])
                }

                TextField("Tags, separated by commas", text: $tags)

                Section("Checklist") {
                    ForEach($checklist) { $entry in
                        HStack(spacing: 8) {
                            Toggle("", isOn: $entry.isCompleted)
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                            TextField("Checklist item", text: $entry.text)
                            Button(role: .destructive) {
                                checklist.removeAll { $0.id == entry.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        TextField("Add a checklist item", text: $newChecklistText)
                            .onSubmit(addChecklistItem)
                        Button("Add", action: addChecklistItem)
                            .disabled(newChecklistText.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty)
                    }
                }
            }
            .formStyle(.grouped)

            if let error = model.commandError {
                Text(error)
                    .font(OpenLoopVisualSystem.metadata)
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }
        }
        .padding(.top, 34)
        .padding(.horizontal, 36)
        .padding(.bottom, 38)
        .frame(width: 560, height: 600, alignment: .top)
    }

    private func addChecklistItem() {
        let text = newChecklistText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        checklist.append(IntentionChecklistItem(text: text))
        newChecklistText = ""
    }

    private func save() {
        isSaving = true
        Task {
            let saved = await model.organizeOpenLoop(
                item.id,
                heading: heading,
                scheduledAt: hasScheduledDate ? scheduledAt : nil,
                deadline: hasDeadline ? deadline : nil,
                tags: tags.split(separator: ",").map(String.init),
                checklist: checklist
            )
            isSaving = false
            if saved { isPresented = false }
        }
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
        HStack(alignment: .top, spacing: 8) {
            if let openLoop {
                OpenLoopCheckbox(isCompleted: openLoop.state == .closed) {
                    Task { await model.finishOpenLoop(openLoop.intentionID) }
                }
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(OpenLoopVisualSystem.inbox)
                    .frame(
                        width: OpenLoopVisualSystem.checkboxHitSize,
                        height: OpenLoopVisualSystem.checkboxHitSize
                    )
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.text)
                        .font(OpenLoopVisualSystem.rowTitle)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Text(dispositionLabel(item.disposition))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(dispositionTint)
                }

                if item.disposition == .action,
                   let outcome = item.desiredOutcome,
                   let action = item.nextAction {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(outcome)
                            .font(OpenLoopVisualSystem.metadata.weight(.medium))
                        Text(action)
                            .font(OpenLoopVisualSystem.metadata)
                            .foregroundStyle(.secondary)
                    }
                }

                if isEditing {
                    editor
                } else {
                    controls
                }
            }
        }
        .padding(.vertical, 7)
        .openLoopInteractiveRow()
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
                    .openLoopTextField()
                TextField("What is the smallest visible next action?", text: $nextAction)
                    .openLoopTextField()
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
                .buttonStyle(OpenLoopAccessoryButtonStyle(tint: .secondary))
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
                .buttonStyle(OpenLoopAccessoryButtonStyle())
                .disabled(model.isSavingReview)
            }
        }
        .padding(11)
        .background(OpenLoopVisualSystem.raised)
        .clipShape(RoundedRectangle(cornerRadius: OpenLoopVisualSystem.editorRadius))
        .overlay {
            RoundedRectangle(cornerRadius: OpenLoopVisualSystem.editorRadius)
                .stroke(OpenLoopVisualSystem.hairline, lineWidth: 0.75)
        }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 12) {
            if let openLoop {
                if openLoop.state == .open {
                    Button("Start focus") {
                        Task { await model.startFocus(openLoop.intentionID) }
                    }
                    .buttonStyle(OpenLoopAccessoryButtonStyle())
                }

                Button("Finish") {
                    Task { await model.finishOpenLoop(openLoop.intentionID) }
                }
                .buttonStyle(OpenLoopAccessoryButtonStyle(tint: .secondary))

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
                    .buttonStyle(OpenLoopAccessoryButtonStyle())
                } else {
                    Button("Review") {
                        resetDraft()
                        isEditing = true
                    }
                    .buttonStyle(OpenLoopAccessoryButtonStyle(tint: .secondary))
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

    private var dispositionTint: Color {
        switch item.disposition {
        case .action: OpenLoopVisualSystem.act
        case .memory: OpenLoopVisualSystem.context
        case .later: OpenLoopVisualSystem.later
        case .release: .secondary
        case .unclear: OpenLoopVisualSystem.emerging
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
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(kindTint)
                .frame(width: OpenLoopVisualSystem.checkboxSize, height: OpenLoopVisualSystem.checkboxSize)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.statement)
                    .font(OpenLoopVisualSystem.rowTitle)
                    .textSelection(.enabled)
                HStack(spacing: 5) {
                    Text(record.kind.rawValue.capitalized)
                        .foregroundStyle(kindTint)
                    Text("·")
                    Text(stateLabel)
                    Text("·")
                    Text(evidenceLabel)
                }
                .font(OpenLoopVisualSystem.metadata)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .openLoopInteractiveRow()
        .accessibilityElement(children: .combine)
    }

    private var stateLabel: String {
        switch record.state {
        case .active: "Current"
        case .contradicted: "Contradicted"
        case .superseded: "Superseded"
        case .evidenceExpired: "Evidence expired"
        }
    }

    private var evidenceLabel: String {
        let retained = record.evidence.filter { $0.availability == .retained }.count
        let expired = record.evidence.count - retained
        if expired == 0 { return "\(retained) evidence retained" }
        return "\(retained) retained · \(expired) expired"
    }

    private var kindTint: Color {
        switch record.kind.rawValue.lowercased() {
        case "decision": OpenLoopVisualSystem.today
        case "preference": OpenLoopVisualSystem.context
        case "procedure": OpenLoopVisualSystem.later
        default: OpenLoopVisualSystem.accent
        }
    }
}

private struct SemanticSectionTitle: View {
    let title: String
    let detail: String

    var body: some View {
        OpenLoopSectionHeading(title: title, tint: OpenLoopVisualSystem.context, detail: detail)
        .padding(.top, 4)
    }
}

private struct SemanticNodeRow: View {
    let node: SemanticNode
    let showEvidence: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(node.kind.rawValue.capitalized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(kindTint)
                Spacer()
                Text("\(Int((node.confidence * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(node.claim)
                .font(OpenLoopVisualSystem.rowTitleEmphasized)
                .textSelection(.enabled)
            if showEvidence, let evidence = node.evidence.first {
                Label(evidence.excerpt, systemImage: "quote.opening")
                    .font(OpenLoopVisualSystem.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            HStack(spacing: 7) {
                Text(node.status.rawValue.capitalized)
                Text("·")
                Text(node.createdAt, style: .relative)
            }
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kindTint: Color {
        if node.status == .speculative { return OpenLoopVisualSystem.today }
        switch node.kind.rawValue.lowercased() {
        case "decision": return OpenLoopVisualSystem.today
        case "problem", "question": return OpenLoopVisualSystem.returnColor
        case "idea", "possibility": return OpenLoopVisualSystem.context
        case "action", "intention": return OpenLoopVisualSystem.later
        default: return OpenLoopVisualSystem.accent
        }
    }
}

private struct SemanticThreadRow: View {
    let thread: SemanticThread

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(thread.node.claim)
                    .font(OpenLoopVisualSystem.rowTitleEmphasized)
                Spacer()
                Text("Strength \(thread.strength)")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
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
                                .font(OpenLoopVisualSystem.metadata)
                                .foregroundStyle(OpenLoopVisualSystem.context)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    OpenLoopVisualSystem.context.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                )
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct RecallEvidenceRow: View {
    let hit: RecallHit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(hit.title).font(OpenLoopVisualSystem.rowTitleEmphasized)
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
        case .capture: "Capture"
        case .intention: "Intention"
        case .returnPacket: "Return point"
        case .correction: "Voice correction"
        case .memory: "Memory"
        case .meetingTranscript: "Meeting transcript"
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
                Text("Why now · \(suggestion.why)")
                    .font(OpenLoopVisualSystem.metadata)
                    .foregroundStyle(OpenLoopVisualSystem.context)
                ForEach(suggestion.contributions) { contribution in
                    RelevanceContributionBar(contribution: contribution)
                }
            }
            HStack(spacing: 10) {
                Button("Start") {
                    Task { await model.startSuggestion(suggestion.intentionID) }
                }
                .buttonStyle(OpenLoopAccessoryButtonStyle())
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
            OpenLoopVisualSystem.raised,
            in: RoundedRectangle(cornerRadius: OpenLoopVisualSystem.editorRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: OpenLoopVisualSystem.editorRadius)
                .stroke(OpenLoopVisualSystem.hairline, lineWidth: 0.65)
        }
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
                .buttonStyle(OpenLoopAccessoryButtonStyle())
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
                packetField("Return to", item.desiredOutcome)
                if let justCompleted = item.justCompleted {
                    packetField("Just completed", justCompleted)
                }
                packetField("Next action", item.nextAction, prominent: true)
                if let blocker = item.blocker {
                    packetField("Blocker", blocker)
                }
                if item.references.isEmpty == false {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("References").font(.caption).foregroundStyle(.secondary)
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
                        .buttonStyle(OpenLoopAccessoryButtonStyle())
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
            width: 980,
            height: 720
        ))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarSeparatorStyle = .none
    }

    func show(tab: Int) {
        let selectedDestination = WorkspaceOrientation.destination(atLegacyTab: tab)
        selectedTabForTesting = WorkspaceOrientation.legacyTabOrder.firstIndex(of: selectedDestination) ?? 0
        hostingController.rootView = MainView(model: model, selection: selectedDestination)
        if selectedDestination == .context || selectedDestination == .ask {
            Task { await model.refreshMemory() }
        }
        if selectedDestination == .context
            || selectedDestination == .emerging
            || selectedDestination == .ask {
            Task { await model.refreshSemanticGraph() }
        }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    var isVisibleForTesting: Bool { window.isVisible }
    var windowNumberForTesting: Int { window.windowNumber }
    var contentSizeForTesting: NSSize { window.contentRect(forFrameRect: window.frame).size }

    func closeForTesting() {
        window.close()
    }
}
