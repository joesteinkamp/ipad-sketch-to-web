import Foundation

/// Linear, navigable history of generated code versions.
///
/// Pushing a new version after navigating back discards the forward history,
/// matching the standard browser-style navigation model.
struct GenerationHistory: Equatable, Sendable {
    private(set) var versions: [GeneratedCode] = []
    private(set) var index: Int = -1

    var current: GeneratedCode? {
        versions.indices.contains(index) ? versions[index] : nil
    }

    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < versions.count - 1 }
    var isEmpty: Bool { versions.isEmpty }
    var count: Int { versions.count }

    mutating func push(_ result: GeneratedCode) {
        if index < versions.count - 1 {
            versions = Array(versions.prefix(index + 1))
        }
        versions.append(result)
        index = versions.count - 1
    }

    @discardableResult
    mutating func goBack() -> GeneratedCode? {
        guard canGoBack else { return nil }
        index -= 1
        return versions[index]
    }

    @discardableResult
    mutating func goForward() -> GeneratedCode? {
        guard canGoForward else { return nil }
        index += 1
        return versions[index]
    }
}
