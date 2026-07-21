import SwiftUI

@main
struct ForceCursorWatchApp: App {
    @State private var model = WatchAppModel()

    var body: some Scene {
        WindowGroup {
            WatchContentView(model: model)
        }
    }
}

