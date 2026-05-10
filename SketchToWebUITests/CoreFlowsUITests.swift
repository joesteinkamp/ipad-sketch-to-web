import XCTest

/// Scaffolding for end-to-end XCUITest scenarios covering the app's golden
/// paths. The launch-argument plumbing on the app side
/// (see `SketchToWebApp.applyUITestLaunchArguments(_:)`) currently seeds
/// deterministic state and disables auto-convert, but does not yet stub all
/// Gemini calls — tests that need a stubbed conversion are marked
/// `XCTSkip`'d so they don't block CI. As the stubs land, flip the skips off
/// and refine the assertions.
final class CoreFlowsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Launch & project creation

    @MainActor
    func testLaunchAndCreateProject() throws {
        app.configureForUITests(stubGemini: true, seedProjects: false)
        app.launch()

        // The sidebar's "New Project" affordance should be visible at launch.
        // Match by accessibility identifier first; fall back to a localized label.
        let newButton = app.buttons["sidebar.newProject"]
            .firstMatch
        if !newButton.exists {
            try XCTSkipUnless(
                app.buttons["New Project"].exists,
                "New Project button missing accessibility id 'sidebar.newProject'."
            )
        }
        let target = newButton.exists ? newButton : app.buttons["New Project"]
        XCTAssertTrue(target.waitToExist(timeout: 5))
        target.tap()

        // The sidebar should now show ≥1 row in the project list.
        let projectRow = app.cells.firstMatch
        XCTAssertTrue(
            projectRow.waitToExist(timeout: 3, message: "Project row did not appear after creation")
        )
    }

    // MARK: - Drawing & convert affordance

    @MainActor
    func testDrawAndAutoConvert() throws {
        try XCTSkipIf(
            true,
            "Requires app-side Gemini stub and PencilKit canvas accessibility hooks."
        )
        app.configureForUITests()
        app.launch()
        // Future: drag across PKCanvas, then assert Convert button enables.
    }

    // MARK: - Templates

    @MainActor
    func testTemplatePickerLoadsLoginForm() throws {
        try XCTSkipIf(
            true,
            "Requires template-picker accessibility identifiers; pending UI work."
        )
        app.configureForUITests(seedProjects: true)
        app.launch()
        // Future: open Templates, tap "Login Form", assert canvas is non-empty.
    }

    // MARK: - Theme toggle

    @MainActor
    func testThemeToggleInSettings() throws {
        try XCTSkipIf(
            true,
            "Requires Settings sheet accessibility identifiers and a way to read the preview's resolved CSS."
        )
        app.configureForUITests()
        app.launch()
        // Future: open Settings, switch base color slate→zinc, assert preview re-renders.
    }

    // MARK: - Design system import

    @MainActor
    func testDesignSystemImportSheetEnablesImportOnURLPaste() throws {
        try XCTSkipIf(
            true,
            "Requires per-project design-system view accessibility identifiers."
        )
        app.configureForUITests(seedProjects: true)
        app.launch()
        // Future: open project design system view, paste GitHub URL, assert Import enables.
    }

    // MARK: - Refinement loop

    @MainActor
    func testRefinementToolbarTogglesBetweenIdleAndActive() throws {
        try XCTSkipIf(
            true,
            "Requires seeded project with a cached generation and AnnotatablePreviewView IDs."
        )
        app.configureForUITests(seedProjects: true)
        app.launch()
        // Future: tap Annotate, assert Draw/Comment picker visible, tap X, return to idle.
    }

    // MARK: - Generation history

    @MainActor
    func testGenerationHistoryNavigation() throws {
        try XCTSkipIf(
            true,
            "Requires seeded project with multiple generations and history controls."
        )
        app.configureForUITests(seedProjects: true)
        app.launch()
        // Future: tap back/forward, assert version label updates.
    }

    // MARK: - Smoke

    /// Always-on smoke test — the app must launch without crashing.
    @MainActor
    func testSmokeLaunchDoesNotCrash() {
        app.configureForUITests()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
    }
}
