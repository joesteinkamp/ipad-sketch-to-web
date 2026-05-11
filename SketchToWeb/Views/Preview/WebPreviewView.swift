import SwiftUI
import WebKit

/// A SwiftUI wrapper around WKWebView that renders self-contained HTML content.
///
/// Theme tokens (shadcn base color + light/dark) are injected into the model-generated
/// HTML at render time so the user can re-theme any preview without re-prompting the
/// AI. The active theme is sourced from `@AppStorage` and the SwiftUI environment's
/// `colorScheme` (so "System" follows the iPad's appearance).
struct WebPreviewView: UIViewRepresentable {
    let htmlContent: String

    @AppStorage(ShadcnThemeStorage.baseColorKey)
    private var baseColorRaw: String = ShadcnThemeStorage.defaultBaseColor.rawValue

    @AppStorage(ShadcnThemeStorage.appearanceKey)
    private var appearanceRaw: String = ShadcnThemeStorage.defaultAppearance.rawValue

    @Environment(\.colorScheme) private var systemColorScheme
    @EnvironmentObject private var appState: AppState

    /// Pipeline:
    ///   model-generated HTML
    ///   → `injectTheme` (CSS tokens for shadcn base color + dark class)
    ///   → `injectIconLibrary` (Lucide/Phosphor/Material Symbols CDN tags)
    ///
    /// Order matters only for readability — both injectors are idempotent and
    /// operate on different `<style>`/`<script>` ids, so they don't collide.
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
        let rendered = processedHTML
        // Only reload when the HTML content (or theme-derived output) has actually changed.
        guard context.coordinator.lastLoadedContent != rendered else { return }
        context.coordinator.lastLoadedContent = rendered
        webView.loadHTMLString(rendered, baseURL: nil)
    }

    // MARK: - Coordinator

    final class Coordinator {
        /// Tracks the last loaded HTML so we avoid redundant reloads.
        var lastLoadedContent: String?
    }
}
