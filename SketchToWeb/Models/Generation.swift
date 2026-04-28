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

    /// Compressed (gzipped) PencilKit drawing data.
    var drawingSnapshot: Data

    /// Identifies which design system produced this generation. Defaults to
    /// `"user"` (the user's own design system from the setup sheet); other
    /// values match the `id` of an entry in the public design-system catalog
    /// (e.g. `"material-3"`). Used by the toggle in `PreviewContainerView`
    /// to find a cached generation for a given sketch + DS pair before
    /// triggering a fresh API call.
    var designSystemKey: String = PublicDesignSystem.userDesignSystemKey

    var project: Project?

    init(
        htmlPreview: String,
        reactCode: String,
        drawingSnapshot: Data,
        designSystemKey: String = PublicDesignSystem.userDesignSystemKey,
        project: Project? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.htmlPreview = htmlPreview
        self.reactCode = reactCode
        self.drawingSnapshot = Generation.compress(drawingSnapshot)
        self.designSystemKey = designSystemKey
        self.project = project
    }

    /// Returns the decompressed drawing snapshot data.
    var decompressedSnapshot: Data {
        Generation.decompress(drawingSnapshot)
    }

    // MARK: - Compression

    private static func compress(_ data: Data) -> Data {
        (try? (data as NSData).compressed(using: .zlib)) as Data? ?? data
    }

    private static func decompress(_ data: Data) -> Data {
        (try? (data as NSData).decompressed(using: .zlib)) as Data? ?? data
    }
}
