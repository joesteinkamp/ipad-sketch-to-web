import Foundation
import SwiftData
import PencilKit

/// Persisted record of a single sketch-to-code generation.
/// Each generation captures the drawing state and generated output at a point in time.
@Model
final class Generation {
    var id: UUID
    var createdAt: Date
    var htmlPreview: String
    var reactCode: String
    var drawingSnapshot: Data

    var project: Project?

    init(
        htmlPreview: String,
        reactCode: String,
        drawingSnapshot: Data,
        project: Project? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.htmlPreview = htmlPreview
        self.reactCode = reactCode
        self.drawingSnapshot = drawingSnapshot
        self.project = project
    }
}
