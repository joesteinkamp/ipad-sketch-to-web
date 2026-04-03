import Foundation

/// Describes a UI component that the conversion pipeline can recognize and emit.
/// Loaded from a bundled `component-catalog.json` resource.
struct ComponentDefinition: Codable, Identifiable, Sendable {
    /// Unique component name, e.g. "Button".
    var name: String

    /// Human-readable description of what this component looks like in a hand-drawn sketch,
    /// used as context for the vision model.
    var sketchPattern: String

    /// The shadcn/ui import path, e.g. "@/components/ui/button".
    var shadcnImport: String

    /// Example JSX usage of this component.
    var exampleUsage: String

    var id: String { name }

    // MARK: - Catalog Loading

    /// Loads the component catalog from the app bundle's `component-catalog.json`.
    ///
    /// - Returns: An array of `ComponentDefinition` entries.
    /// - Throws: If the file is missing or cannot be decoded.
    static func loadCatalog() throws -> [ComponentDefinition] {
        guard let url = Bundle.main.url(forResource: "component-catalog", withExtension: "json") else {
            throw CatalogError.fileNotFound("component-catalog.json not found in bundle.")
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([ComponentDefinition].self, from: data)
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
