import Foundation

/// A curated DESIGN.md preset sourced from the [getdesign.md](https://getdesign.md/)
/// collection (mirrored at [VoltAgent/awesome-design-md](https://github.com/VoltAgent/awesome-design-md)).
/// Catalog entries carry only metadata — the DESIGN.md body is fetched lazily by
/// `DesignSystemImporter.fetchPreset(slug:)` and cached on disk.
struct DesignPreset: Codable, Identifiable, Sendable, Hashable {
    /// Lowercase slug used to build the raw DESIGN.md URL, e.g. "apple", "cal-com".
    var slug: String
    var name: String
    var blurb: String
    var category: String

    var id: String { slug }

    /// Loads the bundled preset catalog. Returns an empty array if the resource
    /// is missing so the gallery can render an empty state instead of crashing.
    static func loadCatalog() -> [DesignPreset] {
        guard let url = Bundle.main.url(forResource: "design-presets", withExtension: "json") else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([DesignPreset].self, from: data)
        } catch {
            return []
        }
    }
}
