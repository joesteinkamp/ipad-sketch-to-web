import Foundation
import SwiftUI
import SwiftData
import PencilKit

/// An observable wrapper around common SwiftData operations for `Project` entities.
///
/// Inject a `ModelContext` from the SwiftUI environment when constructing this object,
/// typically via `.environment(\.modelContext)`.
@MainActor
final class ProjectStore: ObservableObject {

    private let modelContext: ModelContext

    /// The most recent save error, if any. Observe this to show an alert/banner.
    @Published var lastSaveError: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - CRUD

    /// Creates a new project with the given name, inserts it into the model context,
    /// and returns the created instance.
    @discardableResult
    func createProject(name: String) -> Project {
        let project = Project(name: name)
        modelContext.insert(project)
        save()
        return project
    }

    /// Deletes the given project from the model context.
    func deleteProject(_ project: Project) {
        modelContext.delete(project)
        save()
    }

    /// Saves a `PKDrawing` to the specified project, updating both the serialized
    /// drawing data and an optional thumbnail.
    ///
    /// - Parameters:
    ///   - drawing: The `PKDrawing` to persist.
    ///   - project: The target project.
    ///   - canvasSize: Canvas size used for thumbnail generation. Defaults to 1024x768.
    func saveDrawing(_ drawing: PKDrawing, to project: Project, canvasSize: CGSize = CGSize(width: 1024, height: 768)) {
        project.drawingData = drawing.dataRepresentation()

        // Generate a small thumbnail for the project list.
        let thumbnailSize = CGSize(width: 256, height: 192)
        let rect = CGRect(origin: .zero, size: thumbnailSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize, format: format)
        let thumbnail = renderer.image { context in
            UIColor.white.setFill()
            context.fill(rect)
            let image = drawing.image(from: CGRect(origin: .zero, size: canvasSize), scale: 1.0)
            image.draw(in: rect)
        }
        project.thumbnailData = thumbnail.jpegData(compressionQuality: 0.7)

        save()
    }

    /// Saves generated code output to the specified project.
    ///
    /// - Parameters:
    ///   - generation: The generated code from the conversion pipeline.
    ///   - project: The target project.
    func saveGeneration(_ generation: GeneratedCode, to project: Project) {
        project.generatedHTML = generation.htmlPreview
        project.generatedReactCode = generation.reactCode
        save()
    }

    // MARK: - Private

    private func save() {
        do {
            try modelContext.save()
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
            print("[ProjectStore] Failed to save model context: \(error.localizedDescription)")
        }
    }
}
