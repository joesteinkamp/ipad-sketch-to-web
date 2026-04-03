import Foundation
import SwiftData

@Model
final class ProjectFolder {
    var id: UUID
    var name: String
    var createdAt: Date
    var colorHex: String

    @Relationship(deleteRule: .nullify, inverse: \Project.folder)
    var projects: [Project]

    init(
        name: String,
        colorHex: String = "#007AFF"
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.colorHex = colorHex
        self.projects = []
    }

    /// Converts the stored hex string to a SwiftUI `Color`.
    var color: Color {
        Color(hex: colorHex) ?? .blue
    }
}

// MARK: - Color Hex Helper

import SwiftUI

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.hasPrefix("#") ? String(hexSanitized.dropFirst()) : hexSanitized

        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16) else {
            return nil
        }

        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
