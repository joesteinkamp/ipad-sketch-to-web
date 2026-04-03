import Foundation

/// Builds complete HTML documents for previewing generated UI code.
enum HTMLTemplateEngine {

    // MARK: - Public API

    /// Returns a complete HTML document that loads Tailwind CSS from the CDN
    /// and applies shadcn/ui-compatible theming via CSS custom properties.
    ///
    /// - Parameter body: Raw HTML to inject inside `<body>`.
    /// - Returns: A fully-formed HTML string ready for `WKWebView`.
    static func buildPreviewHTML(body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
        <script src="https://cdn.tailwindcss.com"></script>
        <style>
        \(themeCSS)
        \(baseCSS)
        \(interactiveCSS)
        </style>
        </head>
        <body>
        \(body)
        \(interactiveScript)
        </body>
        </html>
        """
    }

    /// Returns a complete HTML document with inline CSS instead of external CDN references.
    /// Suitable for offline use or export.
    ///
    /// - Parameters:
    ///   - body: Raw HTML to inject inside `<body>`.
    ///   - bundledCSS: A CSS string (e.g. a pre-built Tailwind stylesheet) to embed inline.
    /// - Returns: A fully-formed, self-contained HTML string.
    static func buildOfflineHTML(body: String, bundledCSS: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
        <style>
        \(bundledCSS)
        \(themeCSS)
        \(baseCSS)
        \(interactiveCSS)
        </style>
        </head>
        <body>
        \(body)
        \(interactiveScript)
        </body>
        </html>
        """
    }

    // MARK: - Private Fragments

    /// CSS custom properties matching shadcn/ui theming conventions.
    private static let themeCSS = """
    :root {
        --background: 0 0% 100%;
        --foreground: 222.2 84% 4.9%;
        --card: 0 0% 100%;
        --card-foreground: 222.2 84% 4.9%;
        --popover: 0 0% 100%;
        --popover-foreground: 222.2 84% 4.9%;
        --primary: 222.2 47.4% 11.2%;
        --primary-foreground: 210 40% 98%;
        --secondary: 210 40% 96.1%;
        --secondary-foreground: 222.2 47.4% 11.2%;
        --muted: 210 40% 96.1%;
        --muted-foreground: 215.4 16.3% 46.9%;
        --accent: 210 40% 96.1%;
        --accent-foreground: 222.2 47.4% 11.2%;
        --destructive: 0 84.2% 60.2%;
        --destructive-foreground: 210 40% 98%;
        --border: 214.3 31.8% 91.4%;
        --input: 214.3 31.8% 91.4%;
        --ring: 222.2 84% 4.9%;
        --radius: 0.5rem;
    }
    """

    /// Base body styles: system font stack, antialiasing, and theme-aware colors.
    private static let baseCSS = """
    *, *::before, *::after {
        box-sizing: border-box;
        margin: 0;
        padding: 0;
    }
    body {
        font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto,
                     'Helvetica Neue', Arial, sans-serif;
        -webkit-font-smoothing: antialiased;
        -moz-osx-font-smoothing: grayscale;
        background-color: hsl(var(--background));
        color: hsl(var(--foreground));
        line-height: 1.5;
    }
    """

    /// Interactive hover, focus, and transition styles for previewed components.
    private static let interactiveCSS = """
    /* Interactive element transitions */
    button, [role="button"], a, input, textarea, select, summary,
    [data-tab-trigger], [data-accordion-trigger], [data-dialog-trigger],
    [data-checkbox] {
        transition: all 0.15s ease;
    }

    /* Button hover and active states */
    button, [role="button"] {
        cursor: pointer;
    }
    button:hover, [role="button"]:hover {
        filter: brightness(0.95);
    }
    button:active, [role="button"]:active {
        transform: scale(0.97);
        filter: brightness(0.90);
    }

    /* Clickable element cursors */
    a, [data-tab-trigger], [data-accordion-trigger], [data-dialog-trigger],
    [data-checkbox], summary, label[for] {
        cursor: pointer;
    }

    /* Input focus ring (shadcn-style) */
    input:focus, textarea:focus, select:focus {
        outline: none;
        box-shadow: 0 0 0 2px hsl(var(--background)), 0 0 0 4px hsl(var(--ring));
        border-color: hsl(var(--ring));
    }

    /* Checkbox visual states */
    [data-checkbox].checked {
        background-color: hsl(var(--primary));
        border-color: hsl(var(--primary));
        color: hsl(var(--primary-foreground));
    }

    /* Tab active state */
    [data-tab-trigger].active {
        border-bottom: 2px solid hsl(var(--primary));
        color: hsl(var(--foreground));
        font-weight: 600;
    }
    [data-tab-trigger]:not(.active) {
        color: hsl(var(--muted-foreground));
    }

    /* Accordion content */
    [data-accordion-content] {
        overflow: hidden;
        transition: max-height 0.2s ease, opacity 0.2s ease;
    }
    [data-accordion-content].collapsed {
        max-height: 0 !important;
        opacity: 0;
        padding-top: 0;
        padding-bottom: 0;
    }

    /* Dialog backdrop */
    [data-dialog-overlay] {
        position: fixed;
        inset: 0;
        background: rgba(0, 0, 0, 0.5);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 50;
        opacity: 0;
        pointer-events: none;
        transition: opacity 0.15s ease;
    }
    [data-dialog-overlay].open {
        opacity: 1;
        pointer-events: auto;
    }
    """

    /// Vanilla JS script that adds interactivity via event delegation on document.body.
    private static let interactiveScript = """
    <script>
    (function() {
        // Ensure no inputs are inadvertently disabled.
        document.querySelectorAll('input, textarea, select').forEach(function(el) {
            el.removeAttribute('disabled');
            el.removeAttribute('readonly');
        });

        // Event delegation on body for all interactive behaviors.
        document.body.addEventListener('click', function(e) {
            var target = e.target.closest('[data-tab-trigger]')
                      || e.target.closest('[data-accordion-trigger]')
                      || e.target.closest('[data-checkbox]')
                      || e.target.closest('[data-dialog-trigger]')
                      || e.target.closest('[data-dialog-close]');
            if (!target) return;

            // --- Tab switching ---
            if (target.hasAttribute('data-tab-trigger')) {
                var tabGroup = target.getAttribute('data-tab-trigger');
                var parent = target.closest('[data-tabs]') || target.parentElement;
                // Deactivate sibling triggers
                parent.querySelectorAll('[data-tab-trigger]').forEach(function(t) {
                    t.classList.remove('active');
                });
                target.classList.add('active');

                // Show/hide corresponding content panels
                var container = target.closest('[data-tabs]') || document.body;
                container.querySelectorAll('[data-tab-content]').forEach(function(panel) {
                    if (panel.getAttribute('data-tab-content') === tabGroup) {
                        panel.style.display = '';
                    } else {
                        panel.style.display = 'none';
                    }
                });
                return;
            }

            // --- Accordion expand/collapse ---
            if (target.hasAttribute('data-accordion-trigger')) {
                var contentId = target.getAttribute('data-accordion-trigger');
                var content = document.querySelector(
                    '[data-accordion-content="' + contentId + '"]'
                );
                if (content) {
                    content.classList.toggle('collapsed');
                    var isOpen = !content.classList.contains('collapsed');
                    target.setAttribute('aria-expanded', isOpen);
                    if (isOpen) {
                        content.style.maxHeight = content.scrollHeight + 'px';
                    }
                }
                return;
            }

            // --- Checkbox toggle ---
            if (target.hasAttribute('data-checkbox')) {
                target.classList.toggle('checked');
                var isChecked = target.classList.contains('checked');
                target.setAttribute('aria-checked', isChecked);
                // If there is a hidden checkbox input inside, sync it.
                var input = target.querySelector('input[type="checkbox"]');
                if (input) input.checked = isChecked;
                return;
            }

            // --- Dialog open ---
            if (target.hasAttribute('data-dialog-trigger')) {
                var dialogId = target.getAttribute('data-dialog-trigger');
                var overlay = document.querySelector(
                    '[data-dialog-overlay="' + dialogId + '"]'
                );
                if (overlay) overlay.classList.add('open');
                return;
            }

            // --- Dialog close ---
            if (target.hasAttribute('data-dialog-close')) {
                var overlay = target.closest('[data-dialog-overlay]');
                if (overlay) overlay.classList.remove('open');
                return;
            }
        });

        // Close dialog when clicking the backdrop (outside dialog content).
        document.body.addEventListener('click', function(e) {
            if (e.target.hasAttribute && e.target.hasAttribute('data-dialog-overlay')) {
                e.target.classList.remove('open');
            }
        });

        // Initialize: collapse accordion sections that start collapsed.
        document.querySelectorAll('[data-accordion-content].collapsed').forEach(function(el) {
            el.style.maxHeight = '0';
        });
    })();
    </script>
    """
}
