import SwiftUI
import PencilKit
import WebKit

/// A view that layers a transparent PencilKit annotation canvas on top of the web preview.
///
/// Users start in `.idle` mode showing a single "Annotate" entry point. Tapping it reveals
/// a toolbar with a Draw / Comment picker. Draw mode enables a red Pencil overlay; Comment
/// mode lets the user drop numbered Figma-style pins and type detailed instructions. Tapping
/// "Refine" composites the strokes + pins onto a screenshot and sends it (with the typed
/// comments) back to the AI for an iterative refinement pass.
struct AnnotatablePreviewView: View {
    let htmlContent: String
    @EnvironmentObject var appState: AppState

    @State private var mode: AnnotationMode = .idle
    @State private var annotationDrawing = PKDrawing()
    @State private var comments: [PreviewComment] = []
    @State private var editingCommentID: UUID?

    /// References to the underlying UIKit views, set via the representable coordinators.
    @State private var webViewReference: WKWebView?
    @State private var canvasViewReference: PKCanvasView?

    private var hasAnnotations: Bool {
        !annotationDrawing.strokes.isEmpty || !comments.isEmpty
    }

    var body: some View {
        ZStack {
            // Layer 1: Web preview underneath.
            SnapshotableWebPreviewView(
                htmlContent: htmlContent,
                webViewRef: $webViewReference
            )

            // Layer 2: PencilKit overlay (draw mode only).
            if mode == .draw {
                AnnotationCanvasView(
                    drawing: $annotationDrawing,
                    canvasViewRef: $canvasViewReference
                )
                .allowsHitTesting(true)
            }

            // Layer 3: Comment pins + tap-to-add (visible whenever annotating).
            if mode != .idle {
                CommentOverlay(
                    comments: $comments,
                    editingID: $editingCommentID,
                    isInteractive: mode == .comment
                )
                .allowsHitTesting(mode == .comment)
            }
        }
        .loadingOverlay(isPresented: appState.isRefining, message: "Refining UI...")
        .overlay(alignment: .bottom) {
            controls
                .padding(.bottom, 16)
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        switch mode {
        case .idle:
            idleButton
        case .draw, .comment:
            activeToolbar
        }
    }

    private var idleButton: some View {
        Button {
            mode = .draw
        } label: {
            Label("Annotate", systemImage: "pencil.tip.crop.circle")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .controlSize(.large)
        .shadow(radius: 2)
    }

    private var activeToolbar: some View {
        HStack(spacing: 12) {
            Button {
                exitAnnotate()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Exit annotate mode")

            Picker("Mode", selection: $mode) {
                Text("Draw").tag(AnnotationMode.draw)
                Text("Comment").tag(AnnotationMode.comment)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Button {
                captureAndRefine()
            } label: {
                Label("Refine", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(appState.isRefining || !hasAnnotations)

            Menu {
                Button(role: .destructive) {
                    clearAll()
                } label: {
                    Label("Clear all", systemImage: "trash")
                }
                .disabled(!hasAnnotations)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func exitAnnotate() {
        mode = .idle
        editingCommentID = nil
    }

    private func clearAll() {
        annotationDrawing = PKDrawing()
        comments = []
        editingCommentID = nil
    }

    // MARK: - Screenshot & Refine

    private func captureAndRefine() {
        guard let webView = webViewReference else { return }

        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Double(webView.bounds.width))

        let canvasSize = webView.bounds.size
        let scale = UIScreen.main.scale
        let drawingSnapshot = annotationDrawing
        let commentsSnapshot = comments

        webView.takeSnapshot(with: config) { image, error in
            guard let webImage = image else { return }

            // Composite the web snapshot, PencilKit annotations, and numbered pins.
            let renderer = UIGraphicsImageRenderer(size: canvasSize)
            let compositeImage = renderer.image { context in
                webImage.draw(in: CGRect(origin: .zero, size: canvasSize))

                let annotationImage = drawingSnapshot.image(
                    from: CGRect(origin: .zero, size: canvasSize),
                    scale: scale
                )
                annotationImage.draw(in: CGRect(origin: .zero, size: canvasSize))

                Self.drawCommentPins(commentsSnapshot, in: context.cgContext)
            }

            guard let pngData = compositeImage.pngData() else { return }

            // Build the textual comment list (only pins with non-empty text).
            let commentTexts: [String] = commentsSnapshot.enumerated().compactMap { index, comment in
                let trimmed = comment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return "Pin \(index + 1): \(trimmed)"
            }

            Task { @MainActor in
                appState.refineResult(
                    annotationImage: pngData,
                    canvasSize: canvasSize,
                    comments: commentTexts
                )
                annotationDrawing = PKDrawing()
                comments = []
                editingCommentID = nil
            }
        }
    }

    private static func drawCommentPins(_ comments: [PreviewComment], in cgContext: CGContext) {
        let pinRadius: CGFloat = 14

        for (index, comment) in comments.enumerated() {
            let center = comment.position
            let rect = CGRect(
                x: center.x - pinRadius,
                y: center.y - pinRadius,
                width: pinRadius * 2,
                height: pinRadius * 2
            )

            cgContext.setFillColor(UIColor.systemRed.cgColor)
            cgContext.fillEllipse(in: rect)
            cgContext.setStrokeColor(UIColor.white.cgColor)
            cgContext.setLineWidth(2)
            cgContext.strokeEllipse(in: rect)

            let number = "\(index + 1)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let textSize = number.size(withAttributes: attrs)
            let textOrigin = CGPoint(
                x: center.x - textSize.width / 2,
                y: center.y - textSize.height / 2
            )
            number.draw(at: textOrigin, withAttributes: attrs)
        }
    }
}

// MARK: - Annotation Mode

enum AnnotationMode: Equatable {
    case idle
    case draw
    case comment
}

// MARK: - Preview Comment

struct PreviewComment: Identifiable, Equatable {
    let id: UUID
    var position: CGPoint
    var text: String

    init(id: UUID = UUID(), position: CGPoint, text: String = "") {
        self.id = id
        self.position = position
        self.text = text
    }
}

// MARK: - CommentOverlay

private struct CommentOverlay: View {
    @Binding var comments: [PreviewComment]
    @Binding var editingID: UUID?
    let isInteractive: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bottom-most: tap target for dropping new pins.
            if isInteractive {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        addComment(at: location)
                    }
            }

            // Pins + active editor on top.
            ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                CommentPinView(
                    index: index + 1,
                    isActive: editingID == comment.id
                )
                .position(comment.position)
                .onTapGesture {
                    editingID = comment.id
                }

                if editingID == comment.id {
                    CommentEditorView(
                        text: Binding(
                            get: { comments[index].text },
                            set: { comments[index].text = $0 }
                        ),
                        onCommit: { editingID = nil }
                    )
                    .frame(width: 240)
                    .position(
                        x: comment.position.x + 24 + 120,
                        y: comment.position.y
                    )
                }
            }
        }
    }

    private func addComment(at point: CGPoint) {
        let new = PreviewComment(position: point)
        comments.append(new)
        editingID = new.id
    }
}

// MARK: - CommentPinView

private struct CommentPinView: View {
    let index: Int
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(radius: isActive ? 4 : 2)

            Text("\(index)")
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
        }
        .frame(width: 28, height: 28)
        .scaleEffect(isActive ? 1.1 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }
}

// MARK: - CommentEditorView

private struct CommentEditorView: View {
    @Binding var text: String
    let onCommit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("Type a comment…", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(onCommit)

            Button {
                onCommit()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.4), lineWidth: 1)
        )
        .shadow(radius: 3)
        .contentShape(Rectangle())
        .onTapGesture {} // Swallow taps so they don't drop a new pin underneath.
        .onAppear { isFocused = true }
    }
}

// MARK: - SnapshotableWebPreviewView

/// A web preview wrapper that exposes a reference to the underlying WKWebView
/// so the parent can call `takeSnapshot` on it.
private struct SnapshotableWebPreviewView: UIViewRepresentable {
    let htmlContent: String
    @Binding var webViewRef: WKWebView?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = true
        webView.scrollView.bounces = true
        webView.backgroundColor = .systemBackground
        webView.allowsLinkPreview = false
        // Disable user interaction so touches pass through to the annotation overlays.
        webView.isUserInteractionEnabled = false

        DispatchQueue.main.async {
            self.webViewRef = webView
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastLoadedContent != htmlContent else { return }
        context.coordinator.lastLoadedContent = htmlContent
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    final class Coordinator {
        var lastLoadedContent: String?
    }
}

// MARK: - AnnotationCanvasView

/// A transparent PencilKit canvas used as an annotation overlay.
/// Uses a red pen by default to distinguish annotations from the original sketch.
private struct AnnotationCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var canvasViewRef: PKCanvasView?

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.delegate = context.coordinator
        canvasView.drawing = drawing

        // Default tool: red pen, width 3 to visually distinguish from original sketch.
        canvasView.tool = PKInkingTool(.pen, color: .systemRed, width: 3)

        context.coordinator.canvasView = canvasView

        DispatchQueue.main.async {
            self.canvasViewRef = canvasView
            canvasView.becomeFirstResponder()
        }

        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        if canvasView.drawing.dataRepresentation() != drawing.dataRepresentation() {
            canvasView.drawing = drawing
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        var canvasView: PKCanvasView?

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
            super.init()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            DispatchQueue.main.async { [weak self] in
                self?.drawing.wrappedValue = canvasView.drawing
            }
        }
    }
}
