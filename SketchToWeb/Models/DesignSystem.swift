import Foundation
import SwiftData
import CryptoKit

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

    /// Slug of the active getdesign.md preset (e.g. "apple"). Kept separate from
    /// `markdownContent` so a user can combine a curated preset with their own
    /// uploaded DESIGN.md and notes.
    var presetSlug: String?

    /// Display name of the active preset (e.g. "Apple"). Cached so the UI
    /// doesn't need to consult the catalog.
    var presetName: String?

    /// Fetched DESIGN.md body for the active preset. Populated lazily by
    /// `DesignSystemImporter.fetchPreset(slug:)` and cached on disk.
    var presetContent: String?

    /// Distilled DESIGN.md produced by `DesignSystemSynthesizer`. When non-nil
    /// and non-empty, this replaces the raw `sourceURLContent` and
    /// `zipExtractedContent` blocks in the conversion prompt.
    var synthesizedMarkdown: String?

    /// Timestamp of the last successful synthesis.
    var synthesizedAt: Date?

    /// SHA-256 hex of the inputs that produced `synthesizedMarkdown`.
    /// Compared against `currentInputFingerprint` to surface a "stale" badge
    /// after the user changes inputs without re-synthesizing.
    var synthesizedInputFingerprint: String?

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
        (presetContent?.isEmpty ?? true) &&
        fontFilePaths.isEmpty &&
        assetFilePaths.isEmpty
    }

    /// True when there's enough material for a synthesis call to be useful.
    /// Mirrors `isEmpty` minus the empty check — synthesizing an empty design
    /// system would produce nothing.
    var hasSynthesisInputs: Bool { !isEmpty }

    /// SHA-256 hex over the current set of synthesis inputs. Recomputed on
    /// every read; cheap relative to the conversion calls that follow it.
    var currentInputFingerprint: String {
        DesignSystemFingerprint.compute(
            companyBlurb: companyBlurb,
            markdownContent: markdownContent,
            sourceURL: sourceURL,
            sourceURLContent: sourceURLContent,
            zipFilename: zipFilename,
            zipExtractedContent: zipExtractedContent,
            presetSlug: presetSlug,
            presetContent: presetContent,
            notes: notes,
            fontFilePaths: fontFilePaths,
            assetFilePaths: assetFilePaths
        )
    }

    /// True when a synthesis exists but its stored fingerprint no longer
    /// matches the current inputs. Drives the "Out of date" badge in the
    /// editor. Manual edits to `synthesizedMarkdown` itself don't mark this
    /// stale — the fingerprint covers inputs, not the synthesis output.
    var isSynthesisStale: Bool {
        guard let synth = synthesizedMarkdown, !synth.isEmpty else { return false }
        return synthesizedInputFingerprint != currentInputFingerprint
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
            presetSlug: presetSlug,
            presetName: presetName,
            presetContent: presetContent,
            fontFileNames: fontFilePaths.map { ($0 as NSString).lastPathComponent },
            assetFileNames: assetFilePaths.map { ($0 as NSString).lastPathComponent },
            synthesizedMarkdown: synthesizedMarkdown,
            synthesizedAt: synthesizedAt
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
    var presetSlug: String? = nil
    var presetName: String? = nil
    var presetContent: String? = nil
    var fontFileNames: [String]
    var assetFileNames: [String]
    var synthesizedMarkdown: String?
    var synthesizedAt: Date?

    var isEmpty: Bool {
        companyBlurb.isEmpty &&
        notes.isEmpty &&
        (markdownContent?.isEmpty ?? true) &&
        (sourceURLContent?.isEmpty ?? true) &&
        (zipExtractedContent?.isEmpty ?? true) &&
        (presetContent?.isEmpty ?? true) &&
        fontFileNames.isEmpty &&
        assetFileNames.isEmpty
    }
}

extension DesignSystemSnapshot {
    /// Backwards-compatible initializer for tests and call sites that
    /// predate the synthesis fields.
    init(
        companyBlurb: String,
        notes: String,
        markdownContent: String?,
        markdownFilename: String?,
        sourceURL: String?,
        sourceURLContent: String?,
        zipExtractedContent: String?,
        zipFilename: String?,
        fontFileNames: [String],
        assetFileNames: [String]
    ) {
        self.init(
            companyBlurb: companyBlurb,
            notes: notes,
            markdownContent: markdownContent,
            markdownFilename: markdownFilename,
            sourceURL: sourceURL,
            sourceURLContent: sourceURLContent,
            zipExtractedContent: zipExtractedContent,
            zipFilename: zipFilename,
            fontFileNames: fontFileNames,
            assetFileNames: assetFileNames,
            synthesizedMarkdown: nil,
            synthesizedAt: nil
        )
    }
}

/// SHA-256 over the inputs that feed `DesignSystemSynthesizer`. Field names
/// are wrapped in delimiters that won't appear in user content so adjacent
/// fields can't collide (e.g. blurb ending with text that matches a URL).
enum DesignSystemFingerprint {
    static func compute(
        companyBlurb: String,
        markdownContent: String?,
        sourceURL: String?,
        sourceURLContent: String?,
        zipFilename: String?,
        zipExtractedContent: String?,
        presetSlug: String?,
        presetContent: String?,
        notes: String,
        fontFilePaths: [String],
        assetFilePaths: [String]
    ) -> String {
        let parts: [String] = [
            companyBlurb,
            markdownContent ?? "",
            sourceURL ?? "",
            sourceURLContent ?? "",
            zipFilename ?? "",
            zipExtractedContent ?? "",
            presetSlug ?? "",
            presetContent ?? "",
            notes,
            fontFilePaths
                .map { ($0 as NSString).lastPathComponent }
                .sorted()
                .joined(separator: ","),
            assetFilePaths
                .map { ($0 as NSString).lastPathComponent }
                .sorted()
                .joined(separator: ",")
        ]
        let joined = parts.joined(separator: "\n--FIELD--\n")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
