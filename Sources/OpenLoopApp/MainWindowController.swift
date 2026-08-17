import ADHDCore
import AppKit
import SwiftUI

private struct MainView: View {
    @ObservedObject var model: AppModel
    @State var selection = 0
    @State private var interruptionItem: NowItem?
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
            if tab == 3 { recallFieldFocused = true }
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
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
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
        Group {
            if model.openLoops.isEmpty && model.later.isEmpty {
                ContentUnavailableView(
                    "Nothing stored yet",
                    systemImage: "tray",
                    description: Text("Captured actions and notes will stay visible here.")
                )
            } else {
                List {
                    if model.openLoops.isEmpty == false {
                        Section("Open loops") {
                            ForEach(model.openLoops) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.desiredOutcome)
                                        .font(.headline)
                                    Text(item.nextAction)
                                        .foregroundStyle(.secondary)
                                    Text(openLoopStateLabel(item.state))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                    if item.state == .open,
                                       let application = model.currentApplication {
                                        Button(
                                            model.isLinked(item.intentionID, to: application)
                                                ? "Stop suggesting here"
                                                : "Suggest in \(application.applicationName)"
                                        ) {
                                            Task {
                                                if model.isLinked(item.intentionID, to: application) {
                                                    await model.unlinkSuggestion(item.intentionID)
                                                } else {
                                                    await model.linkSuggestion(
                                                        item.intentionID,
                                                        to: application
                                                    )
                                                }
                                            }
                                        }
                                        .font(.callout)
                                        .buttonStyle(.link)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                    if model.later.isEmpty == false {
                        Section("Notes and captures") {
                            ForEach(model.later) { item in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.text)
                                    Text(item.disposition.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                }
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
        window.setContentSize(NSSize(width: 660, height: 540))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    }

    func show(tab: Int) {
        selectedTabForTesting = tab
        hostingController.rootView = MainView(model: model, selection: tab)
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
