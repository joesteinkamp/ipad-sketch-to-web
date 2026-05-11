import Foundation
import SwiftData
import PencilKit

@Model
final class Project {
    var id: UUID
    var name: String
    var createdAt: Date
    var drawingData: Data
    var generatedHTML: String?
    var generatedReactCode: String?
    var thumbnailData: Data?
    var folder: ProjectFolder?
    var tags: [String] = []

    /// When `true`, the project ignores the global `DesignSystem` and uses the
    /// fields below instead. When `false`, the project inherits the global
    /// design system. See `ContentView.updateDesignSystemSnapshot()`.
    var usesCustomDesignSystem: Bool = false

    /// Project-scoped getdesign.md preset (e.g. "stripe"). Mirrors
    /// `DesignSystem.presetSlug` semantics.
    var customPresetSlug: String?
    var customPresetName: String?
    var customPresetContent: String?

    /// Project-scoped DESIGN.md upload override.
    var customMarkdownContent: String?
    var customMarkdownFilename: String?

    /// Project-scoped freeform fields. Optional companions to the chosen
    /// preset / markdown.
    var customCompanyBlurb: String = ""
    var customNotes: String = ""

    /// Project-scoped web icon library override. Stored as raw string for the
    /// same schema-stability reason as `DesignSystem.iconLibraryRaw`. Only
    /// consulted when `usesCustomDesignSystem` is true.
    var customIconLibraryRaw: String?

    /// Typed accessor over `customIconLibraryRaw`. Unknown raw values fall
    /// back to `.none`.
    var customIconLibrary: IconLibrary {
        get { customIconLibraryRaw.flatMap(IconLibrary.init(rawValue:)) ?? .none }
        set { customIconLibraryRaw = newValue.isNone ? nil : newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \Generation.project)
    var generations: [Generation] = []

    init(
        name: String,
        drawingData: Data = PKDrawing().dataRepresentation(),
        generatedHTML: String? = nil,
        generatedReactCode: String? = nil,
        thumbnailData: Data? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.drawingData = drawingData
        self.generatedHTML = generatedHTML
        self.generatedReactCode = generatedReactCode
        self.thumbnailData = thumbnailData
    }

    /// Deserializes the stored drawing data back into a `PKDrawing`.
    /// Returns a blank drawing if deserialization fails.
    var drawing: PKDrawing {
        get {
            (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        }
        set {
            drawingData = newValue.dataRepresentation()
        }
    }
}
