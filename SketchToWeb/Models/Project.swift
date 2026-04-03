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
