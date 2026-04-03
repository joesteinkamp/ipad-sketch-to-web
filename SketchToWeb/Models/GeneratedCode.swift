import Foundation

/// The output of the sketch-to-code conversion pipeline.
struct GeneratedCode: Codable, Equatable, Sendable {
    /// Self-contained HTML suitable for rendering in a WKWebView preview.
    var htmlPreview: String

    /// React/JSX source code using shadcn/ui component imports.
    var reactCode: String

    /// Optional structured representation of the component tree
    /// produced by the conversion pipeline.
    var componentTree: [ComponentNode]?
}

// MARK: - ComponentNode

extension GeneratedCode {
    /// A recursive node representing a single UI component and its children.
    struct ComponentNode: Codable, Equatable, Sendable, Identifiable {
        let id: UUID

        /// The component type, e.g. "Button", "Card", "Input".
        var type: String

        /// Key-value pairs of component props (e.g. "variant": "outline").
        var props: [String: String]?

        /// Child components nested inside this node.
        var children: [ComponentNode]?

        init(
            id: UUID = UUID(),
            type: String,
            props: [String: String]? = nil,
            children: [ComponentNode]? = nil
        ) {
            self.id = id
            self.type = type
            self.props = props
            self.children = children
        }
    }
}
