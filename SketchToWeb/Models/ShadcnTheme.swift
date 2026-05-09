import Foundation

/// One of the five shadcn/ui base color presets.
///
/// Token values for each preset come from the upstream shadcn/ui `globals.css`
/// (https://ui.shadcn.com/themes). When porting a new shadcn release, update
/// `ShadcnTheme.tokens(for:isDark:)` below.
enum ShadcnBaseColor: String, CaseIterable, Codable, Sendable, Identifiable {
    case slate, gray, zinc, neutral, stone

    var id: String { rawValue }

    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

/// User-facing appearance choice. `system` defers to the iPad's current trait collection
/// at the call site (see `ShadcnTheme.resolve`).
enum ThemeAppearance: String, CaseIterable, Codable, Sendable, Identifiable {
    case light, dark, system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
}

/// A concrete shadcn theme — base color paired with a resolved light/dark mode.
struct ShadcnTheme: Equatable, Sendable {
    let base: ShadcnBaseColor
    let isDark: Bool

    /// shadcn/ui defaults to a 0.5rem corner radius across all presets.
    static let radius = "0.5rem"

    /// The 19 CSS custom properties expected on `:root` for this theme. The
    /// returned string is the *body* of the rule — without the `:root { … }`
    /// wrapper — so callers can splice it wherever convenient.
    func cssTokens() -> String {
        Self.tokens(for: base, isDark: isDark).cssBody()
    }

    /// Resolves an appearance preference into a concrete (base, isDark) theme.
    /// `system` follows the supplied iPad system preference.
    static func resolve(
        base: ShadcnBaseColor,
        appearance: ThemeAppearance,
        systemPrefersDark: Bool
    ) -> ShadcnTheme {
        let isDark: Bool
        switch appearance {
        case .light: isDark = false
        case .dark: isDark = true
        case .system: isDark = systemPrefersDark
        }
        return ShadcnTheme(base: base, isDark: isDark)
    }

    // MARK: - Token Catalog

    /// HSL token values for each (base, mode) pair, mirroring shadcn/ui's `globals.css`.
    private struct Tokens {
        let background, foreground: String
        let card, cardForeground: String
        let popover, popoverForeground: String
        let primary, primaryForeground: String
        let secondary, secondaryForeground: String
        let muted, mutedForeground: String
        let accent, accentForeground: String
        let destructive, destructiveForeground: String
        let border, input, ring: String

        func cssBody() -> String {
            """
            --background: \(background);
            --foreground: \(foreground);
            --card: \(card);
            --card-foreground: \(cardForeground);
            --popover: \(popover);
            --popover-foreground: \(popoverForeground);
            --primary: \(primary);
            --primary-foreground: \(primaryForeground);
            --secondary: \(secondary);
            --secondary-foreground: \(secondaryForeground);
            --muted: \(muted);
            --muted-foreground: \(mutedForeground);
            --accent: \(accent);
            --accent-foreground: \(accentForeground);
            --destructive: \(destructive);
            --destructive-foreground: \(destructiveForeground);
            --border: \(border);
            --input: \(input);
            --ring: \(ring);
            --radius: \(ShadcnTheme.radius);
            """
        }
    }

    private static func tokens(for base: ShadcnBaseColor, isDark: Bool) -> Tokens {
        switch (base, isDark) {
        case (.slate, false):
            return Tokens(
                background: "0 0% 100%", foreground: "222.2 84% 4.9%",
                card: "0 0% 100%", cardForeground: "222.2 84% 4.9%",
                popover: "0 0% 100%", popoverForeground: "222.2 84% 4.9%",
                primary: "222.2 47.4% 11.2%", primaryForeground: "210 40% 98%",
                secondary: "210 40% 96.1%", secondaryForeground: "222.2 47.4% 11.2%",
                muted: "210 40% 96.1%", mutedForeground: "215.4 16.3% 46.9%",
                accent: "210 40% 96.1%", accentForeground: "222.2 47.4% 11.2%",
                destructive: "0 84.2% 60.2%", destructiveForeground: "210 40% 98%",
                border: "214.3 31.8% 91.4%", input: "214.3 31.8% 91.4%",
                ring: "222.2 84% 4.9%"
            )
        case (.slate, true):
            return Tokens(
                background: "222.2 84% 4.9%", foreground: "210 40% 98%",
                card: "222.2 84% 4.9%", cardForeground: "210 40% 98%",
                popover: "222.2 84% 4.9%", popoverForeground: "210 40% 98%",
                primary: "210 40% 98%", primaryForeground: "222.2 47.4% 11.2%",
                secondary: "217.2 32.6% 17.5%", secondaryForeground: "210 40% 98%",
                muted: "217.2 32.6% 17.5%", mutedForeground: "215 20.2% 65.1%",
                accent: "217.2 32.6% 17.5%", accentForeground: "210 40% 98%",
                destructive: "0 62.8% 30.6%", destructiveForeground: "210 40% 98%",
                border: "217.2 32.6% 17.5%", input: "217.2 32.6% 17.5%",
                ring: "212.7 26.8% 83.9%"
            )

        case (.gray, false):
            return Tokens(
                background: "0 0% 100%", foreground: "224 71.4% 4.1%",
                card: "0 0% 100%", cardForeground: "224 71.4% 4.1%",
                popover: "0 0% 100%", popoverForeground: "224 71.4% 4.1%",
                primary: "220.9 39.3% 11%", primaryForeground: "210 20% 98%",
                secondary: "220 14.3% 95.9%", secondaryForeground: "220.9 39.3% 11%",
                muted: "220 14.3% 95.9%", mutedForeground: "220 8.9% 46.1%",
                accent: "220 14.3% 95.9%", accentForeground: "220.9 39.3% 11%",
                destructive: "0 84.2% 60.2%", destructiveForeground: "210 20% 98%",
                border: "220 13% 91%", input: "220 13% 91%",
                ring: "224 71.4% 4.1%"
            )
        case (.gray, true):
            return Tokens(
                background: "224 71.4% 4.1%", foreground: "210 20% 98%",
                card: "224 71.4% 4.1%", cardForeground: "210 20% 98%",
                popover: "224 71.4% 4.1%", popoverForeground: "210 20% 98%",
                primary: "210 20% 98%", primaryForeground: "220.9 39.3% 11%",
                secondary: "215 27.9% 16.9%", secondaryForeground: "210 20% 98%",
                muted: "215 27.9% 16.9%", mutedForeground: "217.9 10.6% 64.9%",
                accent: "215 27.9% 16.9%", accentForeground: "210 20% 98%",
                destructive: "0 62.8% 30.6%", destructiveForeground: "210 20% 98%",
                border: "215 27.9% 16.9%", input: "215 27.9% 16.9%",
                ring: "216 12.2% 83.9%"
            )

        case (.zinc, false):
            return Tokens(
                background: "0 0% 100%", foreground: "240 10% 3.9%",
                card: "0 0% 100%", cardForeground: "240 10% 3.9%",
                popover: "0 0% 100%", popoverForeground: "240 10% 3.9%",
                primary: "240 5.9% 10%", primaryForeground: "0 0% 98%",
                secondary: "240 4.8% 95.9%", secondaryForeground: "240 5.9% 10%",
                muted: "240 4.8% 95.9%", mutedForeground: "240 3.8% 46.1%",
                accent: "240 4.8% 95.9%", accentForeground: "240 5.9% 10%",
                destructive: "0 84.2% 60.2%", destructiveForeground: "0 0% 98%",
                border: "240 5.9% 90%", input: "240 5.9% 90%",
                ring: "240 10% 3.9%"
            )
        case (.zinc, true):
            return Tokens(
                background: "240 10% 3.9%", foreground: "0 0% 98%",
                card: "240 10% 3.9%", cardForeground: "0 0% 98%",
                popover: "240 10% 3.9%", popoverForeground: "0 0% 98%",
                primary: "0 0% 98%", primaryForeground: "240 5.9% 10%",
                secondary: "240 3.7% 15.9%", secondaryForeground: "0 0% 98%",
                muted: "240 3.7% 15.9%", mutedForeground: "240 5% 64.9%",
                accent: "240 3.7% 15.9%", accentForeground: "0 0% 98%",
                destructive: "0 62.8% 30.6%", destructiveForeground: "0 0% 98%",
                border: "240 3.7% 15.9%", input: "240 3.7% 15.9%",
                ring: "240 4.9% 83.9%"
            )

        case (.neutral, false):
            return Tokens(
                background: "0 0% 100%", foreground: "0 0% 3.9%",
                card: "0 0% 100%", cardForeground: "0 0% 3.9%",
                popover: "0 0% 100%", popoverForeground: "0 0% 3.9%",
                primary: "0 0% 9%", primaryForeground: "0 0% 98%",
                secondary: "0 0% 96.1%", secondaryForeground: "0 0% 9%",
                muted: "0 0% 96.1%", mutedForeground: "0 0% 45.1%",
                accent: "0 0% 96.1%", accentForeground: "0 0% 9%",
                destructive: "0 84.2% 60.2%", destructiveForeground: "0 0% 98%",
                border: "0 0% 89.8%", input: "0 0% 89.8%",
                ring: "0 0% 3.9%"
            )
        case (.neutral, true):
            return Tokens(
                background: "0 0% 3.9%", foreground: "0 0% 98%",
                card: "0 0% 3.9%", cardForeground: "0 0% 98%",
                popover: "0 0% 3.9%", popoverForeground: "0 0% 98%",
                primary: "0 0% 98%", primaryForeground: "0 0% 9%",
                secondary: "0 0% 14.9%", secondaryForeground: "0 0% 98%",
                muted: "0 0% 14.9%", mutedForeground: "0 0% 63.9%",
                accent: "0 0% 14.9%", accentForeground: "0 0% 98%",
                destructive: "0 62.8% 30.6%", destructiveForeground: "0 0% 98%",
                border: "0 0% 14.9%", input: "0 0% 14.9%",
                ring: "0 0% 83.1%"
            )

        case (.stone, false):
            return Tokens(
                background: "0 0% 100%", foreground: "20 14.3% 4.1%",
                card: "0 0% 100%", cardForeground: "20 14.3% 4.1%",
                popover: "0 0% 100%", popoverForeground: "20 14.3% 4.1%",
                primary: "24 9.8% 10%", primaryForeground: "60 9.1% 97.8%",
                secondary: "60 4.8% 95.9%", secondaryForeground: "24 9.8% 10%",
                muted: "60 4.8% 95.9%", mutedForeground: "25 5.3% 44.7%",
                accent: "60 4.8% 95.9%", accentForeground: "24 9.8% 10%",
                destructive: "0 84.2% 60.2%", destructiveForeground: "60 9.1% 97.8%",
                border: "20 5.9% 90%", input: "20 5.9% 90%",
                ring: "20 14.3% 4.1%"
            )
        case (.stone, true):
            return Tokens(
                background: "20 14.3% 4.1%", foreground: "60 9.1% 97.8%",
                card: "20 14.3% 4.1%", cardForeground: "60 9.1% 97.8%",
                popover: "20 14.3% 4.1%", popoverForeground: "60 9.1% 97.8%",
                primary: "60 9.1% 97.8%", primaryForeground: "24 9.8% 10%",
                secondary: "12 6.5% 15.1%", secondaryForeground: "60 9.1% 97.8%",
                muted: "12 6.5% 15.1%", mutedForeground: "24 5.4% 63.9%",
                accent: "12 6.5% 15.1%", accentForeground: "60 9.1% 97.8%",
                destructive: "0 62.8% 30.6%", destructiveForeground: "60 9.1% 97.8%",
                border: "12 6.5% 15.1%", input: "12 6.5% 15.1%",
                ring: "24 5.7% 82.9%"
            )
        }
    }
}

// MARK: - AppStorage Keys & Defaults

/// Centralised keys + defaults so settings UI, preview views, and the AppState
/// resolver all stay in sync.
enum ShadcnThemeStorage {
    static let baseColorKey = "shadcnBaseColor"
    static let appearanceKey = "themeAppearance"

    static let defaultBaseColor: ShadcnBaseColor = .slate
    static let defaultAppearance: ThemeAppearance = .system
}
