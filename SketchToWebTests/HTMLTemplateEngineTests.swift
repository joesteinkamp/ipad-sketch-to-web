import XCTest
@testable import SketchToWeb

final class HTMLTemplateEngineTests: XCTestCase {

    // MARK: - Tailwind CDN

    func testBuildPreviewHTMLIncludesTailwindCDN() {
        let html = HTMLTemplateEngine.buildPreviewHTML(body: "<p>Test</p>")

        XCTAssertTrue(
            html.contains("https://cdn.tailwindcss.com"),
            "Preview HTML should include the Tailwind CSS CDN script tag."
        )
        XCTAssertTrue(
            html.contains("<script"),
            "Preview HTML should contain a <script> tag for Tailwind."
        )
    }

    // MARK: - Body Content Injection

    func testBuildPreviewHTMLInjectsBodyContent() {
        let bodyContent = "<div class=\"card\"><h1>Hello World</h1></div>"
        let html = HTMLTemplateEngine.buildPreviewHTML(body: bodyContent)

        XCTAssertTrue(
            html.contains(bodyContent),
            "Preview HTML should contain the injected body content verbatim."
        )
        // Verify it appears between <body> and </body>
        guard let bodyStart = html.range(of: "<body>"),
              let bodyEnd = html.range(of: "</body>") else {
            XCTFail("Preview HTML should contain <body> and </body> tags.")
            return
        }

        let bodySection = html[bodyStart.upperBound..<bodyEnd.lowerBound]
        XCTAssertTrue(
            bodySection.contains(bodyContent),
            "Injected content should appear within the <body> element."
        )
    }

    func testBuildPreviewHTMLWithEmptyBody() {
        let html = HTMLTemplateEngine.buildPreviewHTML(body: "")

        XCTAssertTrue(html.contains("<body>"))
        XCTAssertTrue(html.contains("</body>"))
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
    }

    // MARK: - CSS Custom Properties

    func testBuildPreviewHTMLContainsCSSCustomProperties() {
        let html = HTMLTemplateEngine.buildPreviewHTML(body: "<p>Test</p>")

        // Verify key shadcn/ui CSS custom properties are present.
        let expectedProperties = [
            "--background",
            "--foreground",
            "--primary",
            "--primary-foreground",
            "--secondary",
            "--muted",
            "--muted-foreground",
            "--accent",
            "--destructive",
            "--border",
            "--input",
            "--ring",
            "--radius",
            "--card",
            "--card-foreground",
            "--popover",
            "--popover-foreground",
        ]

        for property in expectedProperties {
            XCTAssertTrue(
                html.contains(property),
                "Preview HTML should contain the CSS custom property '\(property)'."
            )
        }
    }

    func testBuildPreviewHTMLContainsRootSelector() {
        let html = HTMLTemplateEngine.buildPreviewHTML(body: "<p>Test</p>")

        XCTAssertTrue(
            html.contains(":root"),
            "Preview HTML should define CSS custom properties inside a :root selector."
        )
    }

    // MARK: - Per-Theme Tokens

    /// Each (base color, mode) combination should emit its canonical shadcn HSL value
    /// for `--primary`. If a future shadcn release changes these defaults, update
    /// `ShadcnTheme.tokens(for:isDark:)`.
    func testBuildPreviewHTMLEmitsExpectedPrimaryPerTheme() {
        let cases: [(ShadcnBaseColor, Bool, String)] = [
            (.slate,   false, "222.2 47.4% 11.2%"),
            (.slate,   true,  "210 40% 98%"),
            (.gray,    false, "220.9 39.3% 11%"),
            (.gray,    true,  "210 20% 98%"),
            (.zinc,    false, "240 5.9% 10%"),
            (.zinc,    true,  "0 0% 98%"),
            (.neutral, false, "0 0% 9%"),
            (.neutral, true,  "0 0% 98%"),
            (.stone,   false, "24 9.8% 10%"),
            (.stone,   true,  "60 9.1% 97.8%"),
        ]

        for (base, isDark, expectedPrimary) in cases {
            let theme = ShadcnTheme(base: base, isDark: isDark)
            let html = HTMLTemplateEngine.buildPreviewHTML(body: "<p>Test</p>", theme: theme)
            XCTAssertTrue(
                html.contains("--primary: \(expectedPrimary);"),
                "\(base.rawValue)\(isDark ? " dark" : " light") should emit `--primary: \(expectedPrimary);`."
            )
        }
    }

    func testBuildPreviewHTMLAddsDarkClassWhenDark() {
        let dark = HTMLTemplateEngine.buildPreviewHTML(
            body: "<p>x</p>",
            theme: ShadcnTheme(base: .slate, isDark: true)
        )
        let light = HTMLTemplateEngine.buildPreviewHTML(
            body: "<p>x</p>",
            theme: ShadcnTheme(base: .slate, isDark: false)
        )

        XCTAssertTrue(dark.contains("<html lang=\"en\" class=\"dark\">"))
        XCTAssertFalse(light.contains("class=\"dark\""))
    }

    // MARK: - injectTheme

    private let modelHTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <script src="https://cdn.tailwindcss.com"></script>
    </head>
    <body>
    <button class="bg-[hsl(var(--primary))] text-[hsl(var(--primary-foreground))]">Hi</button>
    </body>
    </html>
    """

    func testInjectThemeAddsStyleBlockBeforeHeadEnd() {
        let themed = HTMLTemplateEngine.injectTheme(
            into: modelHTML,
            theme: ShadcnTheme(base: .zinc, isDark: false)
        )

        XCTAssertTrue(
            themed.contains("<style id=\"\(HTMLTemplateEngine.themeStyleID)\">"),
            "injectTheme should add a uniquely-IDed style block."
        )
        // Zinc light primary should be present.
        XCTAssertTrue(themed.contains("--primary: 240 5.9% 10%;"))
        // Block should appear before </head>, not after <body>.
        let styleIdx = themed.range(of: "<style id=\"\(HTMLTemplateEngine.themeStyleID)\">")!.lowerBound
        let headEndIdx = themed.range(of: "</head>")!.lowerBound
        XCTAssertLessThan(styleIdx, headEndIdx)
    }

    func testInjectThemeAddsDarkClassToHtmlTag() {
        let themed = HTMLTemplateEngine.injectTheme(
            into: modelHTML,
            theme: ShadcnTheme(base: .slate, isDark: true)
        )
        XCTAssertTrue(themed.contains("<html lang=\"en\" class=\"dark\">"))
    }

    func testInjectThemeRemovesDarkClassWhenSwitchingToLight() {
        let darkHTML = HTMLTemplateEngine.injectTheme(
            into: modelHTML,
            theme: ShadcnTheme(base: .slate, isDark: true)
        )
        XCTAssertTrue(darkHTML.contains("class=\"dark\""))

        let lightHTML = HTMLTemplateEngine.injectTheme(
            into: darkHTML,
            theme: ShadcnTheme(base: .slate, isDark: false)
        )
        XCTAssertFalse(
            lightHTML.contains("class=\"dark\""),
            "Switching from dark to light should strip the `dark` class."
        )
    }

    func testInjectThemeIsIdempotent() {
        let onceThemed = HTMLTemplateEngine.injectTheme(
            into: modelHTML,
            theme: ShadcnTheme(base: .stone, isDark: true)
        )
        let twiceThemed = HTMLTemplateEngine.injectTheme(
            into: onceThemed,
            theme: ShadcnTheme(base: .stone, isDark: true)
        )

        XCTAssertEqual(
            onceThemed, twiceThemed,
            "Re-injecting the same theme should be a no-op."
        )

        // And only one theme style block should exist.
        let occurrences = twiceThemed.components(
            separatedBy: "<style id=\"\(HTMLTemplateEngine.themeStyleID)\">"
        ).count - 1
        XCTAssertEqual(occurrences, 1)
    }

    func testInjectThemeReplacesExistingThemeWhenSwitching() {
        let slate = HTMLTemplateEngine.injectTheme(
            into: modelHTML,
            theme: ShadcnTheme(base: .slate, isDark: false)
        )
        let stone = HTMLTemplateEngine.injectTheme(
            into: slate,
            theme: ShadcnTheme(base: .stone, isDark: false)
        )

        // Slate's primary should be gone; stone's should be present.
        XCTAssertFalse(stone.contains("--primary: 222.2 47.4% 11.2%;"))
        XCTAssertTrue(stone.contains("--primary: 24 9.8% 10%;"))

        // And we still have exactly one theme block.
        let occurrences = stone.components(
            separatedBy: "<style id=\"\(HTMLTemplateEngine.themeStyleID)\">"
        ).count - 1
        XCTAssertEqual(occurrences, 1)
    }

    func testInjectThemeOnHTMLWithoutHeadStillProducesStyleBlock() {
        let bare = "<html lang=\"en\"><body><div>hi</div></body></html>"
        let themed = HTMLTemplateEngine.injectTheme(
            into: bare,
            theme: ShadcnTheme(base: .gray, isDark: false)
        )
        XCTAssertTrue(themed.contains("<style id=\"\(HTMLTemplateEngine.themeStyleID)\">"))
        XCTAssertTrue(themed.contains("--primary: 220.9 39.3% 11%;"))
    }

    func testInjectThemePreservesExistingHtmlClasses() {
        let withClasses = """
        <!DOCTYPE html>
        <html lang="en" class="h-full antialiased">
        <head></head>
        <body><p>x</p></body>
        </html>
        """

        let themed = HTMLTemplateEngine.injectTheme(
            into: withClasses,
            theme: ShadcnTheme(base: .slate, isDark: true)
        )

        XCTAssertTrue(themed.contains("h-full"), "Existing classes must be preserved.")
        XCTAssertTrue(themed.contains("antialiased"))
        XCTAssertTrue(themed.contains("dark"), "Dark class should be appended.")
    }

    // MARK: - Theme Resolver

    func testResolveSystemFollowsSystemPreference() {
        let darkPref = ShadcnTheme.resolve(
            base: .slate, appearance: .system, systemPrefersDark: true
        )
        let lightPref = ShadcnTheme.resolve(
            base: .slate, appearance: .system, systemPrefersDark: false
        )
        XCTAssertTrue(darkPref.isDark)
        XCTAssertFalse(lightPref.isDark)
    }

    func testResolveExplicitOverridesSystem() {
        // Even if the system says dark, an explicit `.light` choice should win.
        let resolved = ShadcnTheme.resolve(
            base: .zinc, appearance: .light, systemPrefersDark: true
        )
        XCTAssertFalse(resolved.isDark)
    }

    // MARK: - Offline HTML

    func testBuildOfflineHTMLUsesInlineCSSInsteadOfCDN() {
        let bundledCSS = "/* Bundled Tailwind CSS */ .flex { display: flex; } .p-4 { padding: 1rem; }"
        let bodyContent = "<div class=\"flex p-4\">Offline content</div>"

        let html = HTMLTemplateEngine.buildOfflineHTML(body: bodyContent, bundledCSS: bundledCSS)

        // Should NOT contain CDN reference.
        XCTAssertFalse(
            html.contains("cdn.tailwindcss.com"),
            "Offline HTML should NOT reference the Tailwind CDN."
        )
        XCTAssertFalse(
            html.contains("<script"),
            "Offline HTML should not include a <script> tag for CDN."
        )

        // Should contain the bundled CSS inline.
        XCTAssertTrue(
            html.contains(bundledCSS),
            "Offline HTML should embed the provided bundled CSS inline."
        )

        // Should still contain the body content.
        XCTAssertTrue(
            html.contains(bodyContent),
            "Offline HTML should contain the injected body content."
        )

        // Should still include theme CSS custom properties.
        XCTAssertTrue(
            html.contains("--primary"),
            "Offline HTML should still include shadcn/ui CSS custom properties."
        )
    }

    func testBuildOfflineHTMLIsValidHTMLDocument() {
        let html = HTMLTemplateEngine.buildOfflineHTML(body: "<p>Offline</p>", bundledCSS: "body { margin: 0; }")

        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<html"))
        XCTAssertTrue(html.contains("<head>"))
        XCTAssertTrue(html.contains("</head>"))
        XCTAssertTrue(html.contains("<body>"))
        XCTAssertTrue(html.contains("</body>"))
        XCTAssertTrue(html.contains("</html>"))
    }
}
