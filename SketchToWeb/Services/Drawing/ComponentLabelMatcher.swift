import Foundation

/// Maps freeform OCR text recognized inside a drawn box to a component name from the catalog.
///
/// Accepts common aliases (e.g. `btn` → `Button`, `dropdown` → `Select`) and tolerates small
/// typos via Levenshtein distance, but rejects matches that aren't close enough to any
/// known component name.
enum ComponentLabelMatcher {

    /// Common shorthand and synonyms users are likely to write.
    /// Keys are normalized (lowercased, no punctuation, no whitespace).
    private static let aliases: [String: String] = [
        "btn": "Button",
        "buttons": "Button",
        "input": "Input",
        "textfield": "Input",
        "textinput": "Input",
        "field": "Input",
        "card": "Card",
        "panel": "Card",
        "label": "Label",
        "checkbox": "Checkbox",
        "check": "Checkbox",
        "checkboxes": "Checkbox",
        "radio": "RadioGroup",
        "radios": "RadioGroup",
        "radiobutton": "RadioGroup",
        "radiogroup": "RadioGroup",
        "switch": "Switch",
        "toggle": "Switch",
        "select": "Select",
        "dropdown": "Select",
        "picker": "Select",
        "combobox": "Select",
        "textarea": "Textarea",
        "textbox": "Textarea",
        "multiline": "Textarea",
        "tabs": "Tabs",
        "tab": "Tabs",
        "dialog": "Dialog",
        "modal": "Dialog",
        "popup": "Dialog",
        "nav": "NavigationMenu",
        "navbar": "NavigationMenu",
        "navigation": "NavigationMenu",
        "navigationmenu": "NavigationMenu",
        "menu": "NavigationMenu",
        "table": "Table",
        "grid": "Table",
        "badge": "Badge",
        "tag": "Badge",
        "chip": "Badge",
        "alert": "Alert",
        "warning": "Alert",
        "notification": "Alert",
        "avatar": "Avatar",
        "profile": "Avatar",
        "separator": "Separator",
        "divider": "Separator",
        "hr": "Separator",
        "slider": "Slider",
        "range": "Slider",
        "sheet": "Sheet",
        "drawer": "Sheet",
        "sidebar": "Sheet",
        "accordion": "Accordion",
        "expandable": "Accordion",
        "collapse": "Accordion"
    ]

    /// The result of an attempted match.
    struct Match: Sendable {
        /// The matched component name (e.g. "Button"), exactly as it appears in the catalog.
        let componentName: String
        /// The raw OCR string this match was derived from (for prompt construction and debugging).
        let rawText: String
        /// Match confidence in `[0, 1]`. 1.0 = exact alias hit; lower values reflect typo distance.
        let confidence: Double
    }

    /// Attempts to match an OCR-recognized string against the component catalog.
    ///
    /// - Parameters:
    ///   - text: A candidate string from `VNRecognizeTextRequest`. May contain noise.
    ///   - catalog: The component catalog (typically `ComponentDefinition.loadCatalog()`).
    /// - Returns: A `Match` if the text plausibly names a known component, otherwise `nil`.
    static func match(_ text: String, catalog: [ComponentDefinition]) -> Match? {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return nil }

        // 1. Exact alias hit.
        if let aliased = aliases[normalized] {
            return Match(componentName: aliased, rawText: text, confidence: 1.0)
        }

        // 2. Exact catalog name hit (case-insensitive).
        if let exact = catalog.first(where: { normalize($0.name) == normalized }) {
            return Match(componentName: exact.name, rawText: text, confidence: 1.0)
        }

        // 3. Fuzzy match against aliases and catalog names.
        var bestName: String?
        var bestDistance = Int.max
        var bestVocabLength = 0

        let vocab: [(key: String, name: String)] =
            aliases.map { ($0.key, $0.value) } +
            catalog.map { (normalize($0.name), $0.name) }

        for (key, name) in vocab {
            let distance = levenshtein(normalized, key)
            if distance < bestDistance {
                bestDistance = distance
                bestName = name
                bestVocabLength = key.count
            }
        }

        guard let bestName, let resolved = resolveCatalogName(bestName, catalog: catalog) else {
            return nil
        }

        // Reject matches that are too distant relative to vocab word length.
        // For short words (≤ 5) allow distance 1; for longer allow up to 2.
        let maxAllowed = bestVocabLength <= 5 ? 1 : 2
        guard bestDistance <= maxAllowed else { return nil }

        let confidence = max(0.0, 1.0 - Double(bestDistance) / Double(max(bestVocabLength, 1)))
        return Match(componentName: resolved, rawText: text, confidence: confidence)
    }

    /// Picks the best match across multiple OCR candidates (e.g. `topCandidates(3)`).
    /// Returns the highest-confidence match, or `nil` if none qualify.
    static func bestMatch(among candidates: [String], catalog: [ComponentDefinition]) -> Match? {
        candidates
            .compactMap { match($0, catalog: catalog) }
            .max(by: { $0.confidence < $1.confidence })
    }

    // MARK: - Internals

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.lowercaseLetters.contains($0) || CharacterSet.decimalDigits.contains($0) }
            .reduce(into: "") { $0.append(Character($1)) }
    }

    /// Maps an alias's resolved value (which is already a catalog name) back to its
    /// canonical catalog entry, ensuring the casing matches the catalog exactly.
    private static func resolveCatalogName(_ candidate: String, catalog: [ComponentDefinition]) -> String? {
        if catalog.contains(where: { $0.name == candidate }) {
            return candidate
        }
        return catalog.first(where: { normalize($0.name) == normalize(candidate) })?.name
    }

    /// Classic iterative Levenshtein distance.
    private static func levenshtein(_ a: String, _ b: String) -> Int {
        if a == b { return 0 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        let aChars = Array(a)
        let bChars = Array(b)
        var previous = Array(0...bChars.count)
        var current = Array(repeating: 0, count: bChars.count + 1)

        for i in 1...aChars.count {
            current[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = Swift.min(
                    current[j - 1] + 1,
                    previous[j] + 1,
                    previous[j - 1] + cost
                )
            }
            swap(&previous, &current)
        }
        return previous[bChars.count]
    }
}
