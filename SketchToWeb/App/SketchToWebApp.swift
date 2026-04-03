import SwiftUI
import SwiftData

@main
struct SketchToWebApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .modelContainer(for: [Project.self, ProjectFolder.self, Generation.self])
    }
}
