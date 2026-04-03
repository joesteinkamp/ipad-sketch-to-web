import SwiftUI
import PencilKit
import WebKit

/// A view that layers a transparent PencilKit annotation canvas on top of the web preview.
///
/// Users can draw red annotations (circles, arrows, handwritten text) over the generated
/// preview and then tap "Refine" to send the annotated screenshot back to the AI for
/// an iterative refinement pass.
struct AnnotatablePreviewView: View {
    let htmlContent: String
    @EnvironmentObject var appState: AppState

    @State private var annotationDrawing = PKDrawing()
    @State private var isAnnotationVisible = true

    /// References to the underlying UIKit views, set via the representable coordinators.
    @State private var webViewReference: WKWebView?
    @State private var canvasViewReference: PKCanvasView?

    var body: some View {
        ZStack {
            // Layer 1: Web preview underneath.
            SnapshotableWebPreviewView(
                htmlContent: htmlContent,
                webViewRef: $webViewReference
            )

            // Layer 2: Transparent PencilKit annotation overlay.
            if isAnnotationVisible {
                AnnotationCanvasView(
                    drawing: $annotationDrawing,
                    canvasViewRef: $canvasViewReference
                )
                .allowsHitTesting(true)
            }
        }
        .loadingOverlay(isPresented: appState.isRefining, message: "Refining UI...")
        .overlay(alignment: .bottom) {
            annotationToolbar
                .padding(.bottom, 16)
        }
    }

    // MARK: - Toolbar

    private var annotationToolbar: some View {
        HStack(spacing: 12) {
            Button {
                captureAndRefine()
            } label: {
                Label("Refine", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(appState.isRefining || annotationDrawing.strokes.isEmpty)

            Button {
                annotationDrawing = PKDrawing()
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(annotationDrawing.strokes.isEmpty)

            Button {
                isAnnotationVisible.toggle()
            } label: {
                Label(
                    isAnnotationVisible ? "Hide Overlay" : "Show Overlay",
                    systemImage: isAnnotationVisible ? "eye.slash" : "eye"
                )
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Screenshot & Refine

    private func captureAndRefine() {
        guard let webView = webViewReference else { return }

        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Double(webView.bounds.width))

        webView.takeSnapshot(with: config) { image, error in
            guard let webImage = image else { return }

            let canvasSize = webView.bounds.size
            let scale = UIScreen.main.scale

            // Composite the web snapshot and PencilKit annotations.
            let renderer = UIGraphicsImageRenderer(size: canvasSize)
            let compositeImage = renderer.image { context in
                // Draw the web view snapshot.
                webImage.draw(in: CGRect(origin: .zero, size: canvasSize))

                // Draw PencilKit annotations on top.
                let annotationImage = annotationDrawing.image(
                    from: CGRect(origin: .zero, size: canvasSize),
                    scale: scale
                )
                annotationImage.draw(in: CGRect(origin: .zero, size: canvasSize))
            }

            guard let pngData = compositeImage.pngData() else { return }

            Task { @MainActor in
                appState.refineResult(annotationImage: pngData, canvasSize: canvasSize)
                // Clear annotations after sending.
                annotationDrawing = PKDrawing()
            }
        }
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
        // Disable user interaction so touches pass through to the PencilKit overlay.
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
