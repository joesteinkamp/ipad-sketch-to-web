import XCTest
@testable import SketchToWeb

/// Verifies the shadcn/ui theme catalog: token presence, structural shape,
/// HSL formatting, and `resolve(...)` semantics.
final class ShadcnThemeTests: XCTestCase {

    // MARK: - Token Presence (all 5 bases × {light, dark})

    /// Every base × mode combination must declare the full set of 19 shadcn tokens
    /// plus `--radius`. Missing one would silently break theming for that mode.
    func testCSSTokensIncludesAllExpectedVariablesForEveryBaseAndMode() {
        let expectedVars = [
            "--background", "--foreground",
            "--card", "--card-foreground",
            "--popover", "--popover-foreground",
            "--primary", "--primary-foreground",
            "--secondary", "--secondary-foreground",
            "--muted", "--muted-foreground",
            "--accent", "--accent-foreground",
            "--destructive", "--destructive-foreground",
            "--border", "--input", "--ring",
            "--radius",
        ]

        for base in ShadcnBaseColor.allCases {
            for isDark in [false, true] {
                let theme = ShadcnTheme(base: base, isDark: isDark)
                let css = theme.cssTokens()
                for variable in expectedVars {
                    XCTAssertTrue(
                        css.contains(variable),
                        "ShadcnTheme(base: .\(base.rawValue), isDark: \(isDark)) missing \(variable)"
                    )
                }
            }
        }
    }

    func testCSSTokensAlwaysDeclares0_5remRadius() {
        for base in ShadcnBaseColor.allCases {
            for isDark in [false, true] {
                let css = ShadcnTheme(base: base, isDark: isDark).cssTokens()
                XCTAssertTrue(
                    css.contains("--radius: 0.5rem"),
                    "Theme \(base) dark=\(isDark) should pin radius to 0.5rem"
                )
            }
        }
    }

    /// Each emitted color value must be HSL-shaped (`H S% L%`) — the format shadcn
    /// expects when downstream CSS uses `hsl(var(--background))`.
    func testHSLValuesUseShadcnHSLFormat() throws {
        // Match e.g. "222.2 84% 4.9%" or "0 0% 100%".
        let regex = try NSRegularExpression(
            pattern: #"^[0-9]+(\.[0-9]+)? [0-9]+(\.[0-9]+)?% [0-9]+(\.[0-9]+)?%$"#
        )
        for base in ShadcnBaseColor.allCases {
            for isDark in [false, true] {
                let css = ShadcnTheme(base: base, isDark: isDark).cssTokens()
                for line in css.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    // `--radius: 0.5rem;` is the one non-HSL token; skip it.
                    guard trimmed.hasPrefix("--"), !trimmed.contains("rem") else { continue }
                    guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
                    let valuePart = trimmed[trimmed.index(after: colonIdx)...]
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
                    let range = NSRange(valuePart.startIndex..., in: valuePart)
                    XCTAssertNotNil(
                        regex.firstMatch(in: valuePart, options: [], range: range),
                        "Token in (\(base), dark=\(isDark)) is not HSL-shaped: \(line)"
                    )
                }
            }
        }
    }

    // MARK: - Light vs Dark Differ

    /// Light and dark variants of the same base must not be identical. Catches
    /// copy-paste mistakes in the token catalog.
    func testLightAndDarkProduceDifferentTokens() {
        for base in ShadcnBaseColor.allCases {
            let light = ShadcnTheme(base: base, isDark: false).cssTokens()
            let dark = ShadcnTheme(base: base, isDark: true).cssTokens()
            XCTAssertNotEqual(light, dark, "Base .\(base) has identical light and dark tokens")
        }
    }

    /// The five base palettes are visually distinct; verify their light tokens differ.
    func testEachBasePaletteIsDistinctInLightMode() {
        let lights = ShadcnBaseColor.allCases.map {
            ShadcnTheme(base: $0, isDark: false).cssTokens()
        }
        let unique = Set(lights)
        XCTAssertEqual(unique.count, lights.count, "Two bases share identical light tokens")
    }

    // MARK: - resolve()

    func testResolveLightAlwaysProducesLightTheme() {
        for base in ShadcnBaseColor.allCases {
            let theme = ShadcnTheme.resolve(base: base, appearance: .light, systemPrefersDark: true)
            XCTAssertFalse(theme.isDark, "Resolving .light should override system prefersDark")
            XCTAssertEqual(theme.base, base)
        }
    }

    func testResolveDarkAlwaysProducesDarkTheme() {
        for base in ShadcnBaseColor.allCases {
            let theme = ShadcnTheme.resolve(base: base, appearance: .dark, systemPrefersDark: false)
            XCTAssertTrue(theme.isDark, "Resolving .dark should override system prefersDark")
            XCTAssertEqual(theme.base, base)
        }
    }

    func testResolveSystemFollowsSystemPreference() {
        let dark = ShadcnTheme.resolve(base: .slate, appearance: .system, systemPrefersDark: true)
        XCTAssertTrue(dark.isDark)

        let light = ShadcnTheme.resolve(base: .slate, appearance: .system, systemPrefersDark: false)
        XCTAssertFalse(light.isDark)
    }

    // MARK: - Equatable

    func testThemeEquatable() {
        XCTAssertEqual(
            ShadcnTheme(base: .zinc, isDark: true),
            ShadcnTheme(base: .zinc, isDark: true)
        )
        XCTAssertNotEqual(
            ShadcnTheme(base: .zinc, isDark: true),
            ShadcnTheme(base: .zinc, isDark: false)
        )
        XCTAssertNotEqual(
            ShadcnTheme(base: .zinc, isDark: true),
            ShadcnTheme(base: .stone, isDark: true)
        )
    }

    // MARK: - Storage Defaults

    func testStorageDefaultsAreSlateAndSystem() {
        XCTAssertEqual(ShadcnThemeStorage.defaultBaseColor, .slate)
        XCTAssertEqual(ShadcnThemeStorage.defaultAppearance, .system)
    }

    // MARK: - Display Names

    func testBaseColorDisplayNamesAreCapitalised() {
        for base in ShadcnBaseColor.allCases {
            let name = base.displayName
            XCTAssertEqual(name.first?.isUppercase, true, "\(name) should start with capital")
            XCTAssertEqual(name.lowercased(), base.rawValue)
        }
    }

    func testAppearanceDisplayNamesAreHumanReadable() {
        XCTAssertEqual(ThemeAppearance.light.displayName, "Light")
        XCTAssertEqual(ThemeAppearance.dark.displayName, "Dark")
        XCTAssertEqual(ThemeAppearance.system.displayName, "System")
    }
}
