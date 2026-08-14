import AppKit
import SwiftUI

private struct MainView: View {
    @ObservedObject var model: AppModel
    @State var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            nowView.tag(0).tabItem { Text("Now") }
            laterView.tag(1).tabItem { Text("Later") }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 360)
        .task { await model.refresh() }
    }

    @ViewBuilder private var nowView: some View {
        if let item = model.now {
            VStack(alignment: .leading, spacing: 18) {
                Text(item.desiredOutcome).font(.title2).fontWeight(.semibold)
                Text("NEXT ACTION").font(.caption).foregroundStyle(.secondary)
                Text(item.nextAction).font(.title3)
                Spacer()
                Text(item.state.rawValue.capitalized).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ContentUnavailableView("Nothing active", systemImage: "circle.dashed")
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
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
            }
        }
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
        window.setContentSize(NSSize(width: 560, height: 420))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    }

    func show(tab: Int) {
        hostingController.rootView = MainView(model: model, selection: tab)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
