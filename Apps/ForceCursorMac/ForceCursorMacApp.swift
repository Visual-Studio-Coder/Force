import SwiftUI

@main
struct ForceCursorMacApp: App {
    @State private var model = MacAppModel()

    var body: some Scene {
        WindowGroup("ForceCursor") {
            MacContentView(model: model)
                .frame(minWidth: 460, minHeight: 430)
        }

        MenuBarExtra("ForceCursor", systemImage: model.isWatchConnected ? "cursorarrow.motionlines" : "cursorarrow") {
            Button("Open ForceCursor") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }

            Divider()

            Text(model.connectionSummary)
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}

