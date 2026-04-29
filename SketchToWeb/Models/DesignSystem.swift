import Foundation
import SwiftData

/// Captures design-system context that augments the conversion prompt so the model
/// produces output that matches the user's brand, tokens, and component conventions.
///
/// The app stores a single active `DesignSystem` (looked up via `fetchOrCreate`).
/// Sources are kept as separate fields so the setup sheet can show them independently
/// and the user can clear any one without losing the others.
@Model
final class DesignSystem {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date

    /// Short company name and one-line blurb. Mirrors the "Company name and blurb"
    /// field in the setup sheet. Empty string when unset.
    var companyBlurb: String

    /// Free-form notes the user typed into the "Any other notes?" field.
    var notes: String

    /// Markdown content imported from a `DESIGN.md`-style file.
    var markdownContent: String?

    /// Original filename of the imported markdown file, surfaced in the UI so
    /// the user can tell what's loaded.
    var markdownFilename: String?

    /// Raw URL the user pasted (e.g. `https://github.com/owner/repo`). Stored verbatim
    /// so it round-trips in the UI.
    var sourceURL: String?

    /// Text fetched from the source URL (typically `DESIGN.md` or `README.md`).
    var sourceURLContent: String?

    /// Concatenated text extracted from a zip import (relevant files only —
    /// markdown, tailwind config, design-token JSON, package.json).
    var zipExtractedContent: String?

    /// Original zip filename, surfaced in the UI.
    var zipFilename: String?

    /// Sandbox-relative paths to imported font files.
    var fontFilePaths: [String] = []

    /// Sandbox-relative paths to imported asset/logo files.
    var assetFilePaths: [String] = []

    init(
        companyBlurb: String = "",
        notes: String = ""
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.companyBlurb = companyBlurb
        self.notes = notes
    }

    /// True when no source content has been provided. The prompt-building code
    /// uses this to skip the design-system section entirely.
    var isEmpty: Bool {
        companyBlurb.isEmpty &&
        notes.isEmpty &&
        (markdownContent?.isEmpty ?? true) &&
        (sourceURLContent?.isEmpty ?? true) &&
        (zipExtractedContent?.isEmpty ?? true) &&
        fontFilePaths.isEmpty &&
        assetFilePaths.isEmpty
    }

    /// Fetches the single active design system, creating one if none exists.
    ///
    /// The app currently maintains one global design system rather than one per
    /// project. If we later want per-project overrides we can add a relationship
    /// without breaking this lookup.
    @MainActor
    static func fetchOrCreate(in context: ModelContext) -> DesignSystem {
        let descriptor = FetchDescriptor<DesignSystem>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let new = DesignSystem()
        context.insert(new)
        return new
    }

    /// Captures the model's current values into a plain `Sendable` struct so
    /// they can cross actor boundaries (e.g. into a non-isolated prompt builder
    /// or pipeline) without holding a reference to the SwiftData model.
    @MainActor
    func snapshot() -> DesignSystemSnapshot {
        DesignSystemSnapshot(
            companyBlurb: companyBlurb,
            notes: notes,
            markdownContent: markdownContent,
            markdownFilename: markdownFilename,
            sourceURL: sourceURL,
            sourceURLContent: sourceURLContent,
            zipExtractedContent: zipExtractedContent,
            zipFilename: zipFilename,
            fontFileNames: fontFilePaths.map { ($0 as NSString).lastPathComponent },
            assetFileNames: assetFilePaths.map { ($0 as NSString).lastPathComponent }
        )
    }
}

/// Plain-value snapshot of a `DesignSystem` for use outside the main actor.
/// Only includes fields needed for prompt building; file paths are reduced to
/// display names since the model never reads the bytes directly.
struct DesignSystemSnapshot: Sendable, Equatable {
    var companyBlurb: String
    var notes: String
    var markdownContent: String?
    var markdownFilename: String?
    var sourceURL: String?
    var sourceURLContent: String?
    var zipExtractedContent: String?
    var zipFilename: String?
    var fontFileNames: [String]
    var assetFileNames: [String]

    var isEmpty: Bool {
        companyBlurb.isEmpty &&
        notes.isEmpty &&
        (markdownContent?.isEmpty ?? true) &&
        (sourceURLContent?.isEmpty ?? true) &&
        (zipExtractedContent?.isEmpty ?? true) &&
        fontFileNames.isEmpty &&
        assetFileNames.isEmpty
    }
}
