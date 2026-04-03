import SwiftUI
import PencilKit

/// A sheet that lets users describe a UI in natural language, then generates a wireframe
/// sketch on the canvas using the Gemini API to produce SVG which is converted to PKDrawing strokes.
struct TextToSketchSheet: View {

    @Environment(\.dismiss) private var dismiss

    /// Called when a drawing has been generated and should be merged onto the canvas.
    var onDrawingGenerated: (PKDrawing) -> Void

    /// The canvas size used to scale the generated SVG into proper coordinates.
    var canvasSize: CGSize

    @State private var description: String = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Describe the UI you want...", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                        .textFieldStyle(.plain)
                } header: {
                    Text("Description")
                } footer: {
                    Text("Example: \"A pricing page with 3 tiers\" or \"A login form with email and password fields\"")
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        generateSketch()
                    } label: {
                        HStack {
                            Spacer()
                            if isGenerating {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 8)
                                Text("Generating...")
                            } else {
                                Image(systemName: "wand.and.stars")
                                    .padding(.trailing, 4)
                                Text("Generate Sketch")
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Text to Sketch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Generation

    private func generateSketch() {
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isGenerating = true
        errorMessage = nil

        Task {
            do {
                guard let apiKey = KeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
                    throw TextToSketchError.apiKeyMissing
                }

                let model = UserDefaults.standard.string(forKey: "selectedModel") ?? "gemini-3.1-pro-preview"
                let client = GeminiClient(apiKey: apiKey, model: model)

                let systemPrompt = """
                You are a wireframe sketch generator. Given a description of a UI, output simple SVG markup \
                representing a hand-drawn wireframe layout. Use only these SVG elements: <rect>, <line>, \
                <circle>, and <text>.

                Rules:
                - The SVG viewBox should be "0 0 1024 768" (landscape orientation).
                - Use stroke="#000000" fill="none" stroke-width="2" for shapes.
                - Rectangles represent cards, input fields, buttons, and containers.
                - Lines represent dividers and borders.
                - Circles represent icons or avatars.
                - <text> elements represent labels. Use font-size="14" or "18" for headings.
                - Keep the wireframe simple and schematic, like a hand-drawn sketch.
                - Output ONLY the SVG markup. No markdown fences, no explanation.
                - Start with <svg and end with </svg>.
                """

                let userPrompt = "Generate a wireframe SVG for: \(description)"

                let svgResponse = try await client.sendTextMessage(
                    systemPrompt: systemPrompt,
                    userText: userPrompt
                )

                let drawing = SVGToDrawingConverter.convert(svg: svgResponse, canvasSize: canvasSize)

                await MainActor.run {
                    onDrawingGenerated(drawing)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}

// MARK: - Errors

private enum TextToSketchError: LocalizedError {
    case apiKeyMissing

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Gemini API key is not configured. Please add your key in Settings."
        }
    }
}

// MARK: - SVG to PKDrawing Converter

/// Converts simple SVG markup into PencilKit PKDrawing strokes.
///
/// Handles `<rect>`, `<line>`, `<circle>`, and `<text>` elements, mapping each
/// to one or more PKStroke objects drawn with a black pen.
struct SVGToDrawingConverter {

    /// Parses SVG markup and converts recognized elements into a PKDrawing.
    ///
    /// The SVG is expected to use a viewBox of "0 0 1024 768". Coordinates are scaled
    /// proportionally to the provided `canvasSize`.
    ///
    /// - Parameters:
    ///   - svg: The SVG markup string.
    ///   - canvasSize: The target canvas size for coordinate scaling.
    /// - Returns: A PKDrawing containing strokes for all parsed SVG elements.
    static func convert(svg: String, canvasSize: CGSize) -> PKDrawing {
        let parser = SVGParser(svg: svg, canvasSize: canvasSize)
        let strokes = parser.parse()
        return PKDrawing(strokes: strokes)
    }
}

// MARK: - SVG Parser

/// A lightweight XML parser delegate that extracts basic SVG shape elements.
private final class SVGParser: NSObject, XMLParserDelegate {

    private let svgString: String
    private let canvasSize: CGSize
    private var strokes: [PKStroke] = []

    /// The viewBox dimensions parsed from the SVG root. Defaults to 1024x768.
    private var viewBoxWidth: CGFloat = 1024
    private var viewBoxHeight: CGFloat = 768

    init(svg: String, canvasSize: CGSize) {
        // Clean up the SVG string: strip markdown code fences if present.
        var cleaned = svg.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            // Remove opening fence line
            if let endOfFirstLine = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: endOfFirstLine)...])
            }
            // Remove closing fence
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        self.svgString = cleaned
        self.canvasSize = canvasSize
        super.init()
    }

    func parse() -> [PKStroke] {
        guard let data = svgString.data(using: .utf8) else { return [] }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return strokes
    }

    // MARK: - Coordinate Scaling

    private func scaleX(_ x: CGFloat) -> CGFloat {
        (x / viewBoxWidth) * canvasSize.width
    }

    private func scaleY(_ y: CGFloat) -> CGFloat {
        (y / viewBoxHeight) * canvasSize.height
    }

    private func scaleW(_ w: CGFloat) -> CGFloat {
        (w / viewBoxWidth) * canvasSize.width
    }

    private func scaleH(_ h: CGFloat) -> CGFloat {
        (h / viewBoxHeight) * canvasSize.height
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        switch elementName.lowercased() {
        case "svg":
            parseViewBox(from: attributes)

        case "rect":
            handleRect(attributes)

        case "line":
            handleLine(attributes)

        case "circle":
            handleCircle(attributes)

        case "text":
            handleText(attributes)

        default:
            break
        }
    }

    // MARK: - ViewBox

    private func parseViewBox(from attributes: [String: String]) {
        guard let viewBox = attributes["viewBox"] else { return }
        let parts = viewBox.split(separator: " ").compactMap { CGFloat(Double(String($0)) ?? 0) }
        if parts.count >= 4 {
            viewBoxWidth = parts[2]
            viewBoxHeight = parts[3]
        }
    }

    // MARK: - Element Handlers

    private func handleRect(_ attrs: [String: String]) {
        guard let x = cgFloat(attrs["x"]),
              let y = cgFloat(attrs["y"]),
              let w = cgFloat(attrs["width"]),
              let h = cgFloat(attrs["height"]) else { return }

        strokes += SketchTemplates.makeRect(
            x: scaleX(x), y: scaleY(y),
            width: scaleW(w), height: scaleH(h)
        )
    }

    private func handleLine(_ attrs: [String: String]) {
        guard let x1 = cgFloat(attrs["x1"]),
              let y1 = cgFloat(attrs["y1"]),
              let x2 = cgFloat(attrs["x2"]),
              let y2 = cgFloat(attrs["y2"]) else { return }

        strokes += SketchTemplates.makeLine(
            from: CGPoint(x: scaleX(x1), y: scaleY(y1)),
            to: CGPoint(x: scaleX(x2), y: scaleY(y2))
        )
    }

    private func handleCircle(_ attrs: [String: String]) {
        guard let cx = cgFloat(attrs["cx"]),
              let cy = cgFloat(attrs["cy"]),
              let r = cgFloat(attrs["r"]) else { return }

        strokes += SketchTemplates.makeCircle(
            cx: scaleX(cx), cy: scaleY(cy),
            radius: scaleW(r)
        )
    }

    private func handleText(_ attrs: [String: String]) {
        guard let x = cgFloat(attrs["x"]),
              let y = cgFloat(attrs["y"]) else { return }

        // Approximate text as a horizontal line placeholder.
        // Use font-size to estimate width, default to a medium placeholder.
        let fontSize = cgFloat(attrs["font-size"]) ?? 14
        let estimatedWidth = fontSize * 5 // rough approximation

        strokes += SketchTemplates.makeTextPlaceholder(
            x: scaleX(x), y: scaleY(y),
            width: scaleW(estimatedWidth)
        )
    }

    // MARK: - Utility

    private func cgFloat(_ value: String?) -> CGFloat? {
        guard let value, let d = Double(value) else { return nil }
        return CGFloat(d)
    }
}
