import XCTest

/// Shared launch arguments + helpers for UI tests. The app reads these in
/// `SketchToWebApp.init` to short-circuit network calls and seed deterministic
/// SwiftData state.
enum UITestLaunchArgs {
    /// Stubs `GeminiClient` calls with canned offline responses so the canvas
    /// can render a preview without an API key or network.
    static let stubGemini = "--uitest-stub-gemini"

    /// Pre-seeds the SwiftData store with one project containing a cached
    /// `GeneratedCode` fixture, so refinement and history tests don't need to
    /// drive a full conversion first.
    static let seedProjects = "--uitest-seed-projects"

    /// Disables the 3-second auto-convert delay so tests can advance quickly.
    static let disableAutoConvert = "--uitest-disable-auto-convert"
}

extension XCUIApplication {
    /// Configures the app for deterministic UI testing.
    @MainActor
    func configureForUITests(
        stubGemini: Bool = true,
        seedProjects: Bool = false,
        disableAutoConvert: Bool = true
    ) {
        if stubGemini { launchArguments.append(UITestLaunchArgs.stubGemini) }
        if seedProjects { launchArguments.append(UITestLaunchArgs.seedProjects) }
        if disableAutoConvert { launchArguments.append(UITestLaunchArgs.disableAutoConvert) }
        launchEnvironment["UITEST_RUNNING"] = "1"
    }
}

/// Convenience for waiting on an element with a clearer failure message than
/// the default XCTest output. Named distinctly from the framework's
/// `waitForExistence(timeout:)` to avoid recursive overload resolution.
extension XCUIElement {
    @discardableResult
    func waitToExist(
        timeout: TimeInterval = 5,
        message: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        let exists = waitForExistence(timeout: timeout)
        if !exists, let message {
            XCTFail(message, file: file, line: line)
        }
        return exists
    }
}
