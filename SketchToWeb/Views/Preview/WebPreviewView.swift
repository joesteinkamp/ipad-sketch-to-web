import SwiftUI
import WebKit

/// A SwiftUI wrapper around WKWebView that renders self-contained HTML content.
struct WebPreviewView: UIViewRepresentable {
    let htmlContent: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Allow inline media playback and viewport meta tag to work properly.
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = true
        webView.scrollView.bounces = true
        webView.backgroundColor = .systemBackground

        // Disable link preview and file access for safety.
        webView.allowsLinkPreview = false

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload when the HTML content has actually changed.
        guard context.coordinator.lastLoadedContent != htmlContent else { return }
        context.coordinator.lastLoadedContent = htmlContent
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    // MARK: - Coordinator

    final class Coordinator {
        /// Tracks the last loaded HTML so we avoid redundant reloads.
        var lastLoadedContent: String?
    }
}
