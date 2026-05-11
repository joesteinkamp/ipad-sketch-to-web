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

    // MARK: - Icon Library Injection

    func testBuildPreviewHTMLDefaultsToNoIconLibrary() {
        let html = HTMLTemplateEngine.buildPreviewHTML(body: "<p>x</p>")
        XCTAssertFalse(html.contains(HTMLTemplateEngine.iconLibraryContainerID))
        XCTAssertFalse(html.contains(HTMLTemplateEngine.iconLibraryInitScriptID))
    }

    func testBuildPreviewHTMLWithLucideEmbedsScriptAndInitCall() {
        let html = HTMLTemplateEngine.buildPreviewHTML(body: "<p>x</p>", iconLibrary: .lucide)
        XCTAssertTrue(html.contains("unpkg.com/lucide"))
        XCTAssertTrue(html.contains("lucide.createIcons"))
        XCTAssertTrue(html.contains(HTMLTemplateEngine.iconLibraryInitScriptID))
    }

    func testBuildPreviewHTMLWithMaterialSymbolsEmbedsStylesheet() {
        let html = HTMLTemplateEngine.buildPreviewHTML(body: "<p>x</p>", iconLibrary: .materialSymbols)
        XCTAssertTrue(html.contains("fonts.googleapis.com"))
        XCTAssertTrue(html.contains("Material+Symbols"))
    }

    func testBuildPreviewHTMLWithHeroiconsAddsNoCDNTags() {
        // Heroicons is inlined as SVG by the model — no CDN tag should be added.
        let html = HTMLTemplateEngine.buildPreviewHTML(body: "<p>x</p>", iconLibrary: .heroicons)
        XCTAssertFalse(html.contains("unpkg.com"))
        XCTAssertFalse(html.contains("fonts.googleapis.com"))
        XCTAssertFalse(html.contains(HTMLTemplateEngine.iconLibraryInitScriptID))
    }

    func testInjectIconLibraryAddsHeadWrapperAndInitScript() {
        let injected = HTMLTemplateEngine.injectIconLibrary(into: modelHTML, library: .lucide)

        XCTAssertTrue(
            injected.contains("<div id=\"\(HTMLTemplateEngine.iconLibraryContainerID)\""),
            "Should add a uniquely-IDed wrapper element in <head>."
        )
        XCTAssertTrue(injected.contains("unpkg.com/lucide"))

        // Wrapper is in <head>, init <script> is just before </body>.
        let containerIdx = injected.range(of: HTMLTemplateEngine.iconLibraryContainerID)!.lowerBound
        let headEndIdx = injected.range(of: "</head>")!.lowerBound
        let bodyEndIdx = injected.range(of: "</body>")!.lowerBound
        XCTAssertLessThan(containerIdx, headEndIdx)

        let initIdx = injected.range(of: HTMLTemplateEngine.iconLibraryInitScriptID)!.lowerBound
        XCTAssertLessThan(initIdx, bodyEndIdx)
        XCTAssertGreaterThan(initIdx, headEndIdx)
    }

    func testInjectIconLibraryIsIdempotent() {
        let once = HTMLTemplateEngine.injectIconLibrary(into: modelHTML, library: .phosphor)
        let twice = HTMLTemplateEngine.injectIconLibrary(into: once, library: .phosphor)

        XCTAssertEqual(once, twice, "Re-injecting the same library must be a no-op.")

        let wrappers = twice.components(separatedBy: "id=\"\(HTMLTemplateEngine.iconLibraryContainerID)\"").count - 1
        XCTAssertEqual(wrappers, 1, "Only one library wrapper should exist after re-injection.")
    }

    func testInjectIconLibrarySwitchingLibrariesReplacesPriorBlock() {
        let lucid = HTMLTemplateEngine.injectIconLibrary(into: modelHTML, library: .lucide)
        XCTAssertTrue(lucid.contains("unpkg.com/lucide"))
        XCTAssertTrue(lucid.contains("lucide.createIcons"))

        let phosphor = HTMLTemplateEngine.injectIconLibrary(into: lucid, library: .phosphor)
        XCTAssertFalse(phosphor.contains("unpkg.com/lucide"), "Lucide script should be replaced.")
        XCTAssertFalse(phosphor.contains("lucide.createIcons"), "Lucide init should be replaced.")
        XCTAssertTrue(phosphor.contains("@phosphor-icons/web"))

        let wrappers = phosphor.components(separatedBy: "id=\"\(HTMLTemplateEngine.iconLibraryContainerID)\"").count - 1
        XCTAssertEqual(wrappers, 1)
    }

    func testInjectIconLibraryWithNoneStripsAnyPriorInjection() {
        let withLucide = HTMLTemplateEngine.injectIconLibrary(into: modelHTML, library: .lucide)
        XCTAssertTrue(withLucide.contains("unpkg.com/lucide"))

        let stripped = HTMLTemplateEngine.injectIconLibrary(into: withLucide, library: .none)
        XCTAssertFalse(stripped.contains("unpkg.com/lucide"))
        XCTAssertFalse(stripped.contains(HTMLTemplateEngine.iconLibraryContainerID))
        XCTAssertFalse(stripped.contains(HTMLTemplateEngine.iconLibraryInitScriptID))
    }

    // MARK: - Body Force-Override

    /// The whole point of the toggle is that the page background flips when the
    /// user picks Dark or a different base color. Gemini routinely emits
    /// `<body class="bg-white …">`, whose `.bg-white` (specificity 0,0,1,0)
    /// beats any non-important `body { background: … }` (0,0,0,1) we inject.
    /// The injected theme block must therefore force body bg/fg via
    /// `!important` so the toggle is visibly responsive.
    func testInjectThemeForcesBodyBackgroundAndForeground() {
        let themed = HTMLTemplateEngine.injectTheme(
            into: modelHTML,
            theme: ShadcnTheme(base: .slate, isDark: true)
        )

        XCTAssertTrue(
            themed.contains("background-color: hsl(var(--background)) !important"),
            "Body background must be forced via !important so model classes like bg-white don't override the theme."
        )
        XCTAssertTrue(
            themed.contains("color: hsl(var(--foreground)) !important"),
            "Body foreground must be forced via !important for the same reason."
        )
    }

    // MARK: - Tailwind Config Injection

    func testInjectThemeAddsTailwindConfigScript() {
        let themed = HTMLTemplateEngine.injectTheme(
            into: modelHTML,
            theme: ShadcnTheme(base: .slate, isDark: false)
        )
        XCTAssertTrue(
            themed.contains("<script id=\"\(HTMLTemplateEngine.tailwindConfigScriptID)\">"),
            "Tailwind config script must be injected so darkMode and named colors apply."
        )
    }

    func testTailwindConfigEnablesClassDarkMode() {
        let themed = HTMLTemplateEngine.injectTheme(
            into: modelHTML,
            theme: ShadcnTheme(base: .slate, isDark: false)
        )
        // The CDN defaults to `darkMode: 'media'`; we need `'class'` so the
        // `dark` class we toggle on <html> actually drives `dark:` variants.
        XCTAssertTrue(
            themed.contains("darkMode: 'class'"),
            "Tailwind config must set darkMode to 'class' so the dark class on <html> drives dark: variants."
        )
    }

    func testTailwindConfigRegistersShadcnSemanticColors() {
        let themed = HTMLTemplateEngine.injectTheme(
            into: modelHTML,
            theme: ShadcnTheme(base: .slate, isDark: false)
        )
        // A representative sampling — exhaustive coverage would just duplicate
        // the source. We care that the named-color extend block reaches the page.
        XCTAssertTrue(themed.contains("background: 'hsl(var(--background))'"))
        XCTAssertTrue(themed.contains("DEFAULT: 'hsl(var(--primary))'"))
        XCTAssertTrue(themed.contains("DEFAULT: 'hsl(var(--card))'"))
        XCTAssertTrue(themed.contains("foreground: 'hsl(var(--card-foreground))'"))
    }

    func testInjectThemeIsIdempotentForConfigScript() {
        let onceThemed = HTMLTemplateEngine.injectTheme(
            into: modelHTML,
            theme: ShadcnTheme(base: .stone, isDark: true)
        )
        let twiceThemed = HTMLTemplateEngine.injectTheme(
            into: onceThemed,
            theme: ShadcnTheme(base: .stone, isDark: true)
        )

        // Exactly one config script after repeated injection.
        let occurrences = twiceThemed.components(
            separatedBy: "<script id=\"\(HTMLTemplateEngine.tailwindConfigScriptID)\">"
        ).count - 1
        XCTAssertEqual(occurrences, 1, "Repeated injectTheme must not stack config scripts.")
    }

    func testInjectIconLibraryAndThemeDoNotInterfere() {
        // The two injectors target different IDs and different parts of <head>.
        // Running them in either order should leave both blocks intact.
        let withTheme = HTMLTemplateEngine.injectTheme(
            into: modelHTML,
            theme: ShadcnTheme(base: .zinc, isDark: false)
        )
        let withBoth = HTMLTemplateEngine.injectIconLibrary(into: withTheme, library: .lucide)

        XCTAssertTrue(withBoth.contains(HTMLTemplateEngine.themeStyleID))
        XCTAssertTrue(withBoth.contains(HTMLTemplateEngine.iconLibraryContainerID))
        XCTAssertTrue(withBoth.contains("--primary: 240 5.9% 10%;"))
        XCTAssertTrue(withBoth.contains("unpkg.com/lucide"))

        // Re-running theme on top of icon-injected HTML shouldn't strip the icon block.
        let rethemed = HTMLTemplateEngine.injectTheme(
            into: withBoth,
            theme: ShadcnTheme(base: .stone, isDark: true)
        )
        XCTAssertTrue(rethemed.contains("unpkg.com/lucide"))
        XCTAssertTrue(rethemed.contains(HTMLTemplateEngine.iconLibraryContainerID))
    }
}
