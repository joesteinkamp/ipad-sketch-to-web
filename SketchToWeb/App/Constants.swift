import SwiftUI

// MARK: - Timing Constants

enum TimingConstants {
    static let drawingDebounce: Duration = .milliseconds(500)
    static let autoConvertDelay: Duration = .seconds(3)
    static let hintDuration: Duration = .seconds(2)
    static let toastDuration: TimeInterval = 1.5
    static let errorBannerTimeout: TimeInterval = 5.0
    static let bannerDismissAnimation: TimeInterval = 0.3
}

// MARK: - App Colors

enum AppColors {
    static let tagPalette: [Color] = [
        .blue, .purple, .orange, .green, .pink, .teal, .indigo, .red, .mint, .cyan
    ]

    static let folderPalette: [(name: String, hex: String)] = [
        ("Blue", "#007AFF"),
        ("Purple", "#AF52DE"),
        ("Green", "#34C759"),
        ("Orange", "#FF9500"),
        ("Red", "#FF3B30"),
        ("Teal", "#5AC8FA"),
        ("Pink", "#FF2D55"),
        ("Indigo", "#5856D6"),
    ]

    /// Deterministic color based on a string hash.
    static func color(for tag: String) -> Color {
        let index = abs(tag.hashValue) % tagPalette.count
        return tagPalette[index]
    }
}

// MARK: - Drawing Tool Types

enum DrawingTool: Equatable, Sendable {
    case pen
    case eraser
}

enum PenThickness: CGFloat, CaseIterable, Identifiable {
    case thin = 1.5
    case medium = 3.0
    case thick = 6.0

    var id: CGFloat { rawValue }

    var label: String {
        switch self {
        case .thin: return "Thin"
        case .medium: return "Medium"
        case .thick: return "Thick"
        }
    }
}
