import Foundation
import PencilKit
import UIKit

/// Provides pre-built wireframe template drawings that users can drop onto the canvas.
///
/// Each template is constructed programmatically using PencilKit strokes to represent
/// common UI layout patterns. Text labels are approximated as short horizontal lines
/// of varying width.
enum SketchTemplates {

    // MARK: - Stroke Construction Helpers

    /// The ink used for all template strokes: a black pen at width 2.
    private static let ink = PKInkingTool(.pen, color: .black, width: 2)

    /// Creates an array of PKStrokes forming a rectangle outline.
    ///
    /// - Parameters:
    ///   - x: The x origin of the rectangle.
    ///   - y: The y origin of the rectangle.
    ///   - width: The width of the rectangle.
    ///   - height: The height of the rectangle.
    /// - Returns: An array of PKStroke (four line segments).
    static func makeRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> [PKStroke] {
        let topLeft = CGPoint(x: x, y: y)
        let topRight = CGPoint(x: x + width, y: y)
        let bottomRight = CGPoint(x: x + width, y: y + height)
        let bottomLeft = CGPoint(x: x, y: y + height)

        return [
            makeSingleLineStroke(from: topLeft, to: topRight),
            makeSingleLineStroke(from: topRight, to: bottomRight),
            makeSingleLineStroke(from: bottomRight, to: bottomLeft),
            makeSingleLineStroke(from: bottomLeft, to: topLeft),
        ]
    }

    /// Creates a single straight-line PKStroke between two points.
    ///
    /// - Parameters:
    ///   - from: The start point.
    ///   - to: The end point.
    /// - Returns: A PKStroke representing the line.
    static func makeLine(from: CGPoint, to: CGPoint) -> [PKStroke] {
        [makeSingleLineStroke(from: from, to: to)]
    }

    /// Creates a short horizontal line that visually represents a text placeholder.
    ///
    /// - Parameters:
    ///   - x: The x position of the text start.
    ///   - y: The y position (baseline) of the text.
    ///   - width: The width of the placeholder line.
    /// - Returns: An array containing a single PKStroke.
    static func makeTextPlaceholder(x: CGFloat, y: CGFloat, width: CGFloat) -> [PKStroke] {
        [makeSingleLineStroke(from: CGPoint(x: x, y: y), to: CGPoint(x: x + width, y: y))]
    }

    /// Creates a filled rectangle (button-like) by drawing the outline plus a few horizontal fill lines.
    private static func makeFilledRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> [PKStroke] {
        var strokes = makeRect(x: x, y: y, width: width, height: height)
        // Add a centered text placeholder inside
        let textWidth = width * 0.6
        let textX = x + (width - textWidth) / 2
        let textY = y + height / 2
        strokes += makeTextPlaceholder(x: textX, y: textY, width: textWidth)
        return strokes
    }

    /// Internal helper to build a PKStroke from two points.
    private static func makeSingleLineStroke(from: CGPoint, to: CGPoint) -> PKStroke {
        let pointCount = 10
        var points: [PKStrokePoint] = []

        for i in 0...pointCount {
            let t = CGFloat(i) / CGFloat(pointCount)
            let x = from.x + (to.x - from.x) * t
            let y = from.y + (to.y - from.y) * t
            let point = PKStrokePoint(
                location: CGPoint(x: x, y: y),
                timeOffset: TimeInterval(t * 0.1),
                size: CGSize(width: 2, height: 2),
                opacity: 1.0,
                force: 0.5,
                azimuth: 0,
                altitude: .pi / 2
            )
            points.append(point)
        }

        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKStroke(ink: PKInk(.pen, color: .black), path: path)
    }

    /// Creates a circle approximation using line segments.
    static func makeCircle(cx: CGFloat, cy: CGFloat, radius: CGFloat) -> [PKStroke] {
        let segments = 24
        var points: [PKStrokePoint] = []

        for i in 0...segments {
            let angle = (CGFloat(i) / CGFloat(segments)) * 2 * .pi
            let x = cx + radius * cos(angle)
            let y = cy + radius * sin(angle)
            let point = PKStrokePoint(
                location: CGPoint(x: x, y: y),
                timeOffset: TimeInterval(Double(i) * 0.01),
                size: CGSize(width: 2, height: 2),
                opacity: 1.0,
                force: 0.5,
                azimuth: 0,
                altitude: .pi / 2
            )
            points.append(point)
        }

        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return [PKStroke(ink: PKInk(.pen, color: .black), path: path)]
    }

    // MARK: - Templates

    /// Login Form: centered card with title, two input fields, a button, and a link.
    static func loginForm(canvasSize: CGSize) -> PKDrawing {
        let w = canvasSize.width
        let h = canvasSize.height

        // Center card
        let cardW: CGFloat = 340
        let cardH: CGFloat = 380
        let cardX = (w - cardW) / 2
        let cardY = (h - cardH) / 2

        var strokes: [PKStroke] = []

        // Card outline
        strokes += makeRect(x: cardX, y: cardY, width: cardW, height: cardH)

        // Title "Login" placeholder
        strokes += makeTextPlaceholder(x: cardX + 120, y: cardY + 40, width: 100)

        // Email field
        let fieldX = cardX + 30
        let fieldW = cardW - 60
        strokes += makeTextPlaceholder(x: fieldX, y: cardY + 80, width: 50) // label
        strokes += makeRect(x: fieldX, y: cardY + 90, width: fieldW, height: 40)

        // Password field
        strokes += makeTextPlaceholder(x: fieldX, y: cardY + 155, width: 70) // label
        strokes += makeRect(x: fieldX, y: cardY + 165, width: fieldW, height: 40)

        // Sign In button
        let btnW: CGFloat = fieldW
        strokes += makeFilledRect(x: fieldX, y: cardY + 240, width: btnW, height: 44)

        // Forgot password link
        strokes += makeTextPlaceholder(x: cardX + 90, y: cardY + 320, width: 160)

        return PKDrawing(strokes: strokes)
    }

    /// Dashboard: top navbar, left sidebar, main content with 2x2 stat cards.
    static func dashboard(canvasSize: CGSize) -> PKDrawing {
        let w = canvasSize.width
        let h = canvasSize.height

        var strokes: [PKStroke] = []

        // Top navbar
        strokes += makeRect(x: 0, y: 0, width: w, height: 60)
        strokes += makeTextPlaceholder(x: 20, y: 30, width: 120) // logo / title

        // Left sidebar
        let sidebarW: CGFloat = 200
        strokes += makeRect(x: 0, y: 60, width: sidebarW, height: h - 60)

        // Sidebar menu items
        for i in 0..<5 {
            let itemY = CGFloat(90 + i * 40)
            strokes += makeTextPlaceholder(x: 20, y: itemY, width: 140)
        }

        // Main content area - 2x2 grid of stat cards
        let contentX = sidebarW + 30
        let contentY: CGFloat = 90
        let cardW = (w - sidebarW - 90) / 2
        let cardH: CGFloat = 140

        for row in 0..<2 {
            for col in 0..<2 {
                let cx = contentX + CGFloat(col) * (cardW + 30)
                let cy = contentY + CGFloat(row) * (cardH + 30)
                strokes += makeRect(x: cx, y: cy, width: cardW, height: cardH)
                // Stat number
                strokes += makeTextPlaceholder(x: cx + 20, y: cy + 40, width: 80)
                // Stat label
                strokes += makeTextPlaceholder(x: cx + 20, y: cy + 70, width: 120)
            }
        }

        return PKDrawing(strokes: strokes)
    }

    /// Landing Page: hero section with heading, subtext, CTA, 3-column features, footer.
    static func landingPage(canvasSize: CGSize) -> PKDrawing {
        let w = canvasSize.width
        let h = canvasSize.height

        var strokes: [PKStroke] = []

        // Navbar
        strokes += makeRect(x: 0, y: 0, width: w, height: 56)
        strokes += makeTextPlaceholder(x: 20, y: 28, width: 100)
        // Nav links
        for i in 0..<3 {
            strokes += makeTextPlaceholder(x: w - 300 + CGFloat(i) * 90, y: 28, width: 60)
        }

        // Hero section
        let heroY: CGFloat = 56
        let heroH: CGFloat = 260
        strokes += makeRect(x: 0, y: heroY, width: w, height: heroH)
        // Big heading
        strokes += makeTextPlaceholder(x: w / 2 - 150, y: heroY + 60, width: 300)
        // Subtext
        strokes += makeTextPlaceholder(x: w / 2 - 200, y: heroY + 100, width: 400)
        strokes += makeTextPlaceholder(x: w / 2 - 150, y: heroY + 120, width: 300)
        // CTA button
        strokes += makeFilledRect(x: w / 2 - 70, y: heroY + 160, width: 140, height: 44)

        // 3-column feature cards
        let featureY = heroY + heroH + 40
        let featureW = (w - 120) / 3
        let featureH: CGFloat = 180

        for col in 0..<3 {
            let fx = 30 + CGFloat(col) * (featureW + 30)
            strokes += makeRect(x: fx, y: featureY, width: featureW, height: featureH)
            // Icon circle
            strokes += makeCircle(cx: fx + featureW / 2, cy: featureY + 40, radius: 20)
            // Title
            strokes += makeTextPlaceholder(x: fx + featureW / 2 - 50, y: featureY + 80, width: 100)
            // Description lines
            strokes += makeTextPlaceholder(x: fx + 20, y: featureY + 110, width: featureW - 40)
            strokes += makeTextPlaceholder(x: fx + 20, y: featureY + 130, width: featureW - 60)
        }

        // Footer
        let footerY = max(featureY + featureH + 40, h - 60)
        strokes += makeRect(x: 0, y: footerY, width: w, height: 60)
        strokes += makeTextPlaceholder(x: w / 2 - 80, y: footerY + 30, width: 160)

        return PKDrawing(strokes: strokes)
    }

    /// Settings Page: left nav with sections, right content area with form fields and toggles.
    static func settingsPage(canvasSize: CGSize) -> PKDrawing {
        let w = canvasSize.width
        let h = canvasSize.height

        var strokes: [PKStroke] = []

        // Top bar
        strokes += makeRect(x: 0, y: 0, width: w, height: 56)
        strokes += makeTextPlaceholder(x: 20, y: 28, width: 80) // "Settings"

        // Left nav
        let navW: CGFloat = 220
        strokes += makeRect(x: 0, y: 56, width: navW, height: h - 56)

        // Nav sections
        let sections = ["Profile", "Account", "Notifications", "Privacy", "Appearance"]
        for (i, _) in sections.enumerated() {
            let itemY = CGFloat(80 + i * 44)
            strokes += makeTextPlaceholder(x: 20, y: itemY, width: CGFloat(60 + (i % 3) * 20))
        }

        // Right content area
        let contentX = navW + 40
        let contentW = w - navW - 80
        var currentY: CGFloat = 80

        // Section heading
        strokes += makeTextPlaceholder(x: contentX, y: currentY, width: 120)
        currentY += 30

        // Form fields (3 fields with labels)
        for _ in 0..<3 {
            strokes += makeTextPlaceholder(x: contentX, y: currentY, width: 80) // label
            currentY += 12
            strokes += makeRect(x: contentX, y: currentY, width: contentW, height: 36)
            currentY += 56
        }

        // Toggle rows (2 toggles)
        for _ in 0..<2 {
            strokes += makeTextPlaceholder(x: contentX, y: currentY + 8, width: 150)
            // Toggle switch representation
            strokes += makeRect(x: contentX + contentW - 50, y: currentY, width: 44, height: 24)
            strokes += makeCircle(cx: contentX + contentW - 50 + 32, cy: currentY + 12, radius: 9)
            currentY += 48
        }

        // Save button
        strokes += makeFilledRect(x: contentX, y: currentY + 20, width: 120, height: 40)

        return PKDrawing(strokes: strokes)
    }

    /// Pricing Page: heading, 3 pricing tier cards side by side with features and CTA buttons.
    static func pricingPage(canvasSize: CGSize) -> PKDrawing {
        let w = canvasSize.width
        let h = canvasSize.height

        var strokes: [PKStroke] = []

        // Page heading
        strokes += makeTextPlaceholder(x: w / 2 - 100, y: 40, width: 200) // "Pricing"
        strokes += makeTextPlaceholder(x: w / 2 - 160, y: 70, width: 320) // subtitle

        // 3 pricing cards
        let cardW = (w - 120) / 3
        let cardH: CGFloat = max(h - 160, 440)
        let cardY: CGFloat = 110

        for col in 0..<3 {
            let cx = 30 + CGFloat(col) * (cardW + 30)

            strokes += makeRect(x: cx, y: cardY, width: cardW, height: cardH)

            // Tier name
            strokes += makeTextPlaceholder(x: cx + cardW / 2 - 40, y: cardY + 30, width: 80)

            // Price
            strokes += makeTextPlaceholder(x: cx + cardW / 2 - 30, y: cardY + 65, width: 60)

            // Divider
            strokes += makeLine(
                from: CGPoint(x: cx + 20, y: cardY + 90),
                to: CGPoint(x: cx + cardW - 20, y: cardY + 90)
            )

            // Feature list (5 items)
            for i in 0..<5 {
                let featureY = cardY + 120 + CGFloat(i) * 32
                // Checkmark circle
                strokes += makeCircle(cx: cx + 30, cy: featureY, radius: 6)
                // Feature text
                let featureWidth = CGFloat(80 + (i * 17) % 60)
                strokes += makeTextPlaceholder(x: cx + 50, y: featureY, width: featureWidth)
            }

            // CTA button at bottom of card
            let btnY = cardY + cardH - 70
            strokes += makeFilledRect(x: cx + 20, y: btnY, width: cardW - 40, height: 44)
        }

        return PKDrawing(strokes: strokes)
    }

    // MARK: - Template Catalog

    /// A template entry with a name and its generator function.
    struct Template: Identifiable {
        let id = UUID()
        let name: String
        let iconName: String
        let generator: (CGSize) -> PKDrawing
    }

    /// All available templates.
    static let all: [Template] = [
        Template(name: "Login Form", iconName: "person.crop.square", generator: loginForm),
        Template(name: "Dashboard", iconName: "chart.bar.doc.horizontal", generator: dashboard),
        Template(name: "Landing Page", iconName: "globe", generator: landingPage),
        Template(name: "Settings Page", iconName: "gearshape", generator: settingsPage),
        Template(name: "Pricing Page", iconName: "tag", generator: pricingPage),
    ]
}
