import Foundation

/// Progress states yielded by `DesignExportPipeline` while sending a sketch + code
/// to a remote design tool's MCP server.
enum DesignExportState: Equatable, Sendable {
    /// Resolving OAuth, listing tools, preparing the request.
    case connecting

    /// The orchestrator is iterating; `step` is a short human description of what's
    /// happening right now (e.g. "Creating Login frame", "Adding email input").
    case working(step: String)

    /// Completed successfully. `fileURL` is a Figma file URL to open.
    case completed(fileURL: URL?)

    /// Failed. `message` is user-facing.
    case failed(message: String)

    var isTerminal: Bool {
        switch self {
        case .completed, .failed:
            return true
        case .connecting, .working:
            return false
        }
    }
}
