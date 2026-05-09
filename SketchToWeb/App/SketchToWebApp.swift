import SwiftUI
import SwiftData

@main
struct SketchToWebApp: App {
    @StateObject private var appState: AppState

    init() {
        _appState = StateObject(wrappedValue: AppState())
        #if DEBUG
        Self.applyUITestLaunchArguments(ProcessInfo.processInfo.arguments)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .modelContainer(for: [Project.self, ProjectFolder.self, Generation.self, DesignSystem.self])
    }

    #if DEBUG
    /// Honors the launch arguments declared in
    /// `SketchToWebUITests/UITestFixtures.swift`. Only flags toggleable via
    /// `UserDefaults` are wired here today; richer stubs (Gemini canned
    /// responses, SwiftData seeding) are tracked as TODOs in the UI test file.
    private static func applyUITestLaunchArguments(_ args: [String]) {
        if args.contains("--uitest-disable-auto-convert") {
            UserDefaults.standard.set(false, forKey: "autoConvertEnabled")
        }
        // `--uitest-stub-gemini` and `--uitest-seed-projects` are read here but
        // require service-layer wiring that isn't implemented yet. Keeping the
        // flags in one place documents intent for follow-up work.
        _ = args.contains("--uitest-stub-gemini")
        _ = args.contains("--uitest-seed-projects")
    }
    #endif
}
