import Foundation

/// A pre-defined public design system the user can compare their generations
/// against. Loaded from the bundled `public-design-systems.json` catalog.
///
/// The `"shadcn"` entry is treated as the default — when the active key is
/// `shadcn`, the conversion prompt produces the same shadcn/ui output as
/// before and no public-DS section is appended.
struct PublicDesignSystem: Codable, Identifiable, Sendable, Equatable {
    /// Stable identifier (e.g. `"material-3"`). Persisted on `Generation`
    /// records and in `@AppStorage` so it survives launches.
    var id: String

    /// Full display name shown in the picker menu (e.g. `"Material 3"`).
    var name: String

    /// Compact label for the segmented toggle (e.g. `"Material 3"`). Falls
    /// back to `name` when omitted.
    var shortName: String?

    /// One-line summary shown beneath the name in the picker menu.
    var description: String

    /// Marks the catalog's default entry. Exactly one entry should set this.
    /// When the active design system is the default, the prompt builder skips
    /// the public-DS section entirely.
    var isDefault: Bool

    /// Style guidance appended to the conversion / refinement system prompt
    /// when this DS is active. Empty for the default entry.
    var promptFragment: String

    /// Convenience for the toggle UI.
    var displayShortName: String { shortName ?? name }

    // MARK: - Catalog Loading

    static let userDesignSystemKey = "user"

    /// Loads the public-design-systems catalog from the app bundle.
    ///
    /// Checks `Bundle.main` first, then falls back to the bundle that owns
    /// this type so unit tests (whose `Bundle.main` is the test runner) can
    /// still resolve the resource via the app bundle.
    static func loadCatalog() throws -> [PublicDesignSystem] {
        let url = Bundle.main.url(forResource: "public-design-systems", withExtension: "json")
            ?? Bundle(for: BundleAnchor.self).url(forResource: "public-design-systems", withExtension: "json")

        guard let url else {
            throw CatalogError.fileNotFound("public-design-systems.json not found in bundle.")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([PublicDesignSystem].self, from: data)
    }

    /// Looks up an entry by id, returning the catalog default on miss.
    static func entry(forID id: String, in catalog: [PublicDesignSystem]) -> PublicDesignSystem? {
        catalog.first { $0.id == id } ?? catalog.first { $0.isDefault }
    }

    enum CatalogError: LocalizedError {
        case fileNotFound(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let message):
                return message
            }
        }
    }
}

/// Anchor type used purely as a `Bundle(for:)` reference so test runs can
/// locate the bundle that contains the catalog JSON.
private final class BundleAnchor {}

