import ADHDCore
import AppKit
import SwiftUI

private struct MainView: View {
    @ObservedObject var model: AppModel
    @State var selection = 0
    @State private var interruptionItem: NowItem?

    var body: some View {
        TabView(selection: $selection) {
            nowView.tag(0).tabItem { Text("Now") }
            returnView.tag(1).tabItem { Text("Return") }
            laterView.tag(2).tabItem { Text("Later") }
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 460)
        .task { await model.refresh() }
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

    @ViewBuilder private var nowView: some View {
        if let item = model.now {
            VStack(alignment: .leading, spacing: 20) {
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
                Spacer()
                if let error = model.commandError {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                }
                focusControls(item)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ContentUnavailableView(
                model.returns.isEmpty ? "Nothing active" : "Your place is saved",
                systemImage: model.returns.isEmpty ? "circle.dashed" : "arrow.uturn.backward.circle",
                description: Text(
                    model.returns.isEmpty
                        ? "Capture an action when it arrives."
                        : "Open Return when you are ready to continue."
                )
            )
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
        Group {
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
            if model.later.isEmpty {
                ContentUnavailableView("Later is quiet", systemImage: "tray")
            } else {
                List(model.later) { item in
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

    init(model: AppModel) {
        self.model = model
        hostingController = NSHostingController(rootView: MainView(model: model))
        window = NSWindow(contentViewController: hostingController)
        window.title = "OpenLoop ADHD"
        window.setContentSize(NSSize(width: 660, height: 540))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    }

    func show(tab: Int) {
        hostingController.rootView = MainView(model: model, selection: tab)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
