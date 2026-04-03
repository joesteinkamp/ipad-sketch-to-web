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
