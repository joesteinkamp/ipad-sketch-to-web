import Foundation
import ZIPFoundation

/// Imports design-system content from external sources (raw URLs, zip archives,
/// loose files) and reduces them to text the conversion prompt can include.
///
/// Stateless — each method is self-contained so the setup sheet can call them
/// from `Task` blocks and write results back into the `DesignSystem` model.
enum DesignSystemImporter {

    // MARK: - Errors

    enum ImportError: LocalizedError {
        case invalidURL
        case noRelevantFilesInArchive
        case archiveReadFailed(String)
        case httpError(Int)
        case allCandidatesFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "That doesn't look like a valid URL."
            case .noRelevantFilesInArchive:
                return "Couldn't find any DESIGN.md, README, tailwind config, or token files in the archive."
            case .archiveReadFailed(let detail):
                return "Failed to read archive: \(detail)"
            case .httpError(let code):
                return "Server returned HTTP \(code)."
            case .allCandidatesFailed:
                return "Couldn't find a DESIGN.md or README at that URL."
            }
        }
    }

    // MARK: - URL Fetch

    /// Fetches design-system text from a code-host URL. Tries `DESIGN.md`,
    /// `design.md`, then `README.md` in turn. Supports GitHub, GitLab, Bitbucket,
    /// and falls back to treating the input as a raw file URL.
    ///
    /// - Returns: The first successfully fetched body and the URL it came from.
    static func fetchFromSourceURL(_ raw: String) async throws -> (content: String, resolvedURL: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else {
            throw ImportError.invalidURL
        }

        let candidates = candidateRawURLs(for: trimmed)
        var lastError: Error?

        for candidate in candidates {
            do {
                let body = try await fetchText(candidate)
                return (body, candidate)
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? ImportError.allCandidatesFailed
    }

    /// Builds an ordered list of raw-content URLs to try for the user's input.
    /// Public for testability.
    static func candidateRawURLs(for raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let filenames = ["DESIGN.md", "design.md", "README.md", "readme.md"]

        // Already a raw URL? Use it as-is and skip the filename expansion.
        if isLikelyRawFileURL(trimmed) {
            return [trimmed]
        }

        if let host = URL(string: trimmed)?.host?.lowercased() {
            switch host {
            case "github.com":
                if let (owner, repo) = parseOwnerRepo(trimmed, host: "github.com") {
                    return filenames.map {
                        "https://raw.githubusercontent.com/\(owner)/\(repo)/HEAD/\($0)"
                    }
                }
            case "gitlab.com":
                if let (owner, repo) = parseOwnerRepo(trimmed, host: "gitlab.com") {
                    return filenames.map {
                        "https://gitlab.com/\(owner)/\(repo)/-/raw/HEAD/\($0)"
                    }
                }
            case "bitbucket.org":
                if let (owner, repo) = parseOwnerRepo(trimmed, host: "bitbucket.org") {
                    return filenames.map {
                        "https://bitbucket.org/\(owner)/\(repo)/raw/HEAD/\($0)"
                    }
                }
            default:
                break
            }
        }

        // Unknown host: try the URL itself, then probe common filenames at its root.
        var fallbacks = [trimmed]
        if let url = URL(string: trimmed), let base = url.deletingLastPathComponent().absoluteString.nilIfEmpty {
            fallbacks.append(contentsOf: filenames.map { base + $0 })
        }
        return fallbacks
    }

    private static func isLikelyRawFileURL(_ url: String) -> Bool {
        let lowered = url.lowercased()
        return lowered.contains("raw.githubusercontent.com") ||
               lowered.contains("/-/raw/") ||
               lowered.contains("/raw/") ||
               lowered.hasSuffix(".md") ||
               lowered.hasSuffix(".txt") ||
               lowered.hasSuffix(".json")
    }

    private static func parseOwnerRepo(_ url: String, host: String) -> (String, String)? {
        guard let parsed = URL(string: url), parsed.host?.lowercased() == host else {
            return nil
        }
        let parts = parsed.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.count >= 2 else { return nil }
        let repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        return (parts[0], repo)
    }

    private static func fetchText(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw ImportError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/plain, text/markdown, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ImportError.httpError(http.statusCode)
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Zip Extraction

    /// Names matched (case-insensitively) when scanning a zip archive. We pull
    /// just the files most likely to inform design-system context — keeping the
    /// extracted text small enough to fit in the prompt.
    static let relevantArchiveFilenames: Set<String> = [
        "design.md", "design-system.md", "readme.md",
        "tailwind.config.js", "tailwind.config.ts", "tailwind.config.mjs", "tailwind.config.cjs",
        "tokens.json", "design-tokens.json",
        "package.json"
    ]

    /// Extracts and concatenates relevant text files from a zip archive.
    ///
    /// - Parameter zipURL: A file URL pointing to the zip on disk.
    /// - Returns: Concatenated content with `## path/to/file.ext` headers between
    ///   each entry, suitable for embedding in the prompt.
    /// - Throws: `ImportError.archiveReadFailed` if the archive can't be opened,
    ///   `ImportError.noRelevantFilesInArchive` if nothing matched.
    static func extractRelevantText(fromZip zipURL: URL) throws -> String {
        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .read)
        } catch {
            throw ImportError.archiveReadFailed(error.localizedDescription)
        }

        var sections: [String] = []
        let perFileLimit = 4_000
        let totalLimit = 16_000
        var totalSize = 0

        for entry in archive {
            guard entry.type == .file else { continue }

            let lastComponent = (entry.path as NSString).lastPathComponent.lowercased()
            guard relevantArchiveFilenames.contains(lastComponent) else { continue }

            var buffer = Data()
            do {
                _ = try archive.extract(entry, bufferSize: 16_384, skipCRC32: true) { chunk in
                    buffer.append(chunk)
                }
            } catch {
                continue
            }

            guard let text = String(data: buffer, encoding: .utf8), !text.isEmpty else { continue }

            let truncated = text.count > perFileLimit
                ? String(text.prefix(perFileLimit)) + "\n\n... [file truncated]"
                : text

            sections.append("## \(entry.path)\n\(truncated)")
            totalSize += truncated.count
            if totalSize >= totalLimit { break }
        }

        guard !sections.isEmpty else { throw ImportError.noRelevantFilesInArchive }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - File Persistence

    /// Copies a picked file (font, asset) into the app's design-system sandbox
    /// folder so it survives across launches without holding a security-scoped
    /// reference. Returns the new on-disk path.
    static func persistImportedFile(at sourceURL: URL, subfolder: String) throws -> String {
        let directory = try designSystemDirectory().appendingPathComponent(subfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination.path
    }

    private static func designSystemDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("DesignSystem", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
