import SwiftUI
import WebKit

/// A view that layers a comment-pin overlay on top of the web preview.
///
/// Users start in `.idle` mode showing a single "Annotate" entry point. Tapping it
/// switches to comment mode, where the user can tap to drop numbered Figma-style pins
/// and type detailed instructions. Tapping "Refine" composites the numbered pins onto
/// a screenshot and sends it (with the typed comments) back to the AI for an iterative
/// refinement pass.
struct AnnotatablePreviewView: View {
    let htmlContent: String
    @EnvironmentObject var appState: AppState

    @State private var mode: AnnotationMode = .idle
    @State private var comments: [PreviewComment] = []
    @State private var editingCommentID: UUID?

    /// Reference to the underlying WKWebView, set via the representable coordinator.
    @State private var webViewReference: WKWebView?

    private var hasAnnotations: Bool {
        !comments.isEmpty
    }

    var body: some View {
        ZStack {
            // Layer 1: Web preview underneath.
            SnapshotableWebPreviewView(
                htmlContent: htmlContent,
                webViewRef: $webViewReference
            )

            // Layer 2: Comment pins + tap-to-add (visible whenever annotating).
            if mode == .comment {
                CommentOverlay(
                    comments: $comments,
                    editingID: $editingCommentID,
                    isInteractive: true
                )
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
        case .comment:
            activeToolbar
        }
    }

    private var idleButton: some View {
        Button {
            mode = .comment
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
        comments = []
        editingCommentID = nil
    }

    // MARK: - Screenshot & Refine

    private func captureAndRefine() {
        guard let webView = webViewReference else { return }

        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Double(webView.bounds.width))

        let canvasSize = webView.bounds.size
        let commentsSnapshot = comments

        webView.takeSnapshot(with: config) { image, error in
            guard let webImage = image else { return }

            // Composite the web snapshot and numbered pins.
            let renderer = UIGraphicsImageRenderer(size: canvasSize)
            let compositeImage = renderer.image { context in
                webImage.draw(in: CGRect(origin: .zero, size: canvasSize))
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
///
/// Mirrors `WebPreviewView`'s theme-injection behavior so the captured screenshot
/// (used by the refinement pipeline) reflects the user's active theme.
private struct SnapshotableWebPreviewView: UIViewRepresentable {
    let htmlContent: String
    @Binding var webViewRef: WKWebView?

    @AppStorage(ShadcnThemeStorage.baseColorKey)
    private var baseColorRaw: String = ShadcnThemeStorage.defaultBaseColor.rawValue

    @AppStorage(ShadcnThemeStorage.appearanceKey)
    private var appearanceRaw: String = ShadcnThemeStorage.defaultAppearance.rawValue

    @Environment(\.colorScheme) private var systemColorScheme
    @EnvironmentObject private var appState: AppState

    private var processedHTML: String {
        let base = ShadcnBaseColor(rawValue: baseColorRaw) ?? ShadcnThemeStorage.defaultBaseColor
        let appearance = ThemeAppearance(rawValue: appearanceRaw) ?? ShadcnThemeStorage.defaultAppearance
        let theme = ShadcnTheme.resolve(
            base: base,
            appearance: appearance,
            systemPrefersDark: systemColorScheme == .dark
        )
        let themed = HTMLTemplateEngine.injectTheme(into: htmlContent, theme: theme)
        let library = appState.designSystemSnapshot?.iconLibrary ?? .none
        return HTMLTemplateEngine.injectIconLibrary(into: themed, library: library)
    }

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
        let rendered = processedHTML
        guard context.coordinator.lastLoadedContent != rendered else { return }
        context.coordinator.lastLoadedContent = rendered
        webView.loadHTMLString(rendered, baseURL: nil)
    }

    final class Coordinator {
        var lastLoadedContent: String?
    }
}
