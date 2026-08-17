import ADHDCore
import AppKit
import SwiftUI

private struct MainView: View {
    @ObservedObject var model: AppModel
    @State var selection = 0
    @State private var interruptionItem: NowItem?
    @State private var memoryHistoryExpanded = false
    @FocusState private var recallFieldFocused: Bool

    var body: some View {
        TabView(selection: $selection) {
            nowView.tag(0).tabItem { Text("Now") }
            returnView.tag(1).tabItem { Text("Return") }
            laterView.tag(2).tabItem { Text("Later") }
            recallView.tag(3).tabItem { Text("Recall") }
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 460)
        .task { await model.refresh() }
        .onChange(of: selection) { _, tab in
            if tab == 3 {
                recallFieldFocused = true
                Task { await model.refreshMemory() }
            }
        }
        .sheet(isPresented: interruptionPresented) {
            if let item = interruptionItem {
                InterruptionSheet(model: model, item: item) {
                    interruptionItem = nil
                }
            }
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
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Now")
                        .font(.largeTitle.weight(.semibold))
                    Text("One intention, with enough context to return.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let item = model.now {
                    currentIntention(item)
                } else if model.suggestions.isEmpty {
                    ContentUnavailableView(
                        model.returns.isEmpty ? "Nothing active" : "Your place is saved",
                        systemImage: model.returns.isEmpty
                            ? "circle.dashed"
                            : "arrow.uturn.backward.circle",
                        description: Text(
                            model.returns.isEmpty
                                ? "Capture an action when it arrives."
                                : "Open Return when you are ready to continue."
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 330)
                }

                contextTrailPanel

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
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.7))
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Later")
                        .font(.largeTitle.weight(.semibold))
                    Text("A quiet place to decide what a capture means. Nothing here is overdue.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 520, alignment: .leading)
                }

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

    private var recallView: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recall")
                    .font(.largeTitle.weight(.semibold))
                Text("Find stored evidence. Nothing here is generated.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }


            workingMemorySection

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
                Text("⌘⇧F opens Recall")
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
                ScrollView {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { recallFieldFocused = true }
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
            if let openLoop, openLoop.state == .open {
                Button("Start focus") {
                    Task { await model.startFocus(openLoop.intentionID) }
                }
                .buttonStyle(.borderedProminent)
                if let application = model.currentApplication {
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
        window.setContentSize(NSSize(width: 760, height: 620))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    }

    func show(tab: Int) {
        selectedTabForTesting = tab
        hostingController.rootView = MainView(model: model, selection: tab)
        if tab == 3 { Task { await model.refreshMemory() } }
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
