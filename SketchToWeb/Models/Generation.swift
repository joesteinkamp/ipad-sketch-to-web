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
        self.drawingSnapshot = Generation.compress(drawingSnapshot)
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
