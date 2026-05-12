import Foundation

/// Builds complete HTML documents for previewing generated UI code, and injects
/// shadcn/ui theme tokens into model-generated HTML at runtime.
enum HTMLTemplateEngine {

    /// `<style>` `id` used for the runtime-injected token block. Matched by the
    /// idempotency check in `injectTheme(into:theme:)` so repeated calls replace
    /// rather than accumulate.
    static let themeStyleID = "sketch-theme-tokens"

    /// `<script>` `id` for the runtime-injected Tailwind config block. The block
    /// flips Tailwind CDN's `darkMode` to `'class'` (so the `dark` class on
    /// `<html>` actually drives `dark:` variants) and registers shadcn semantic
    /// color names (`bg-primary`, `bg-card`, …) that resolve to the CSS tokens
    /// the theme block defines. Matched by the idempotency check in
    /// `injectTheme(into:theme:)`.
    static let tailwindConfigScriptID = "sketch-tailwind-config"

    /// Wrapper element `id` used to bracket runtime-injected icon-library tags
    /// (script and/or stylesheet). Matched by the idempotency check in
    /// `injectIconLibrary(into:library:)` so repeated calls replace rather than
    /// accumulate, and switching libraries doesn't leave stale tags behind.
    static let iconLibraryContainerID = "sketch-icon-library"

    /// Companion `<script>` `id` for the body-end init script (e.g. Lucide's
    /// `lucide.createIcons()`). Lives outside the head wrapper because it must
    /// run after the body.
    static let iconLibraryInitScriptID = "sketch-icon-library-init"

    // MARK: - Public API

    /// Returns a complete HTML document that loads Tailwind CSS from the CDN
    /// and applies shadcn/ui-compatible theming via CSS custom properties.
    ///
    /// - Parameters:
    ///   - body: Raw HTML to inject inside `<body>`.
    ///   - theme: shadcn theme to apply. Defaults to Slate light to match the
    ///     historical hardcoded values.
    static func buildPreviewHTML(
        body: String,
        theme: ShadcnTheme = ShadcnTheme(base: .slate, isDark: false),
        iconLibrary: IconLibrary = .none
    ) -> String {
        """
        <!DOCTYPE html>
        <html lang="en"\(theme.isDark ? " class=\"dark\"" : "")>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
        <script src="https://cdn.tailwindcss.com"></script>
        <script id="\(tailwindConfigScriptID)">
        \(tailwindConfigJS)
        </script>
        \(iconLibraryHeadBlock(for: iconLibrary))
        <style id="\(themeStyleID)">
        \(themeCSS(for: theme))
        </style>
        <style>
        \(baseCSS)
        \(interactiveCSS)
        </style>
        </head>
        <body>
        \(body)
        \(interactiveScript)
        \(iconLibraryInitBlock(for: iconLibrary))
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
    ///   - theme: shadcn theme to apply.
    static func buildOfflineHTML(
        body: String,
        bundledCSS: String,
        theme: ShadcnTheme = ShadcnTheme(base: .slate, isDark: false),
        iconLibrary: IconLibrary = .none
    ) -> String {
        // TODO: For true offline output we should inline icon-library assets
        // (Material Symbols font, Lucide/Phosphor JS) rather than reference
        // their CDNs. For now we still inject the CDN tags so exported HTML
        // matches the in-app preview when a network is available.
        """
        <!DOCTYPE html>
        <html lang="en"\(theme.isDark ? " class=\"dark\"" : "")>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
        <style>
        \(bundledCSS)
        </style>
        \(iconLibraryHeadBlock(for: iconLibrary))
        <style id="\(themeStyleID)">
        \(themeCSS(for: theme))
        </style>
        <style>
        \(baseCSS)
        \(interactiveCSS)
        </style>
        </head>
        <body>
        \(body)
        \(interactiveScript)
        \(iconLibraryInitBlock(for: iconLibrary))
        </body>
        </html>
        """
    }

    /// Splices a `<style id="sketch-theme-tokens">` block of shadcn token values
    /// into the model-generated HTML and toggles the `dark` class on `<html>`.
    ///
    /// Idempotent: if a previous theme block exists (e.g. because this HTML was
    /// fed back through the refinement loop), it is replaced rather than
    /// appended, so callers can safely re-inject on every render.
    static func injectTheme(into html: String, theme: ShadcnTheme) -> String {
        let styleBlock = """
        <style id="\(themeStyleID)">
        \(themeCSS(for: theme))
        </style>
        """
        let configBlock = """
        <script id="\(tailwindConfigScriptID)">
        \(tailwindConfigJS)
        </script>
        """

        var working = html
        let existingStylePattern = #"<style id="\#(themeStyleID)">[\s\S]*?</style>"#

        if let existing = working.range(of: existingStylePattern, options: .regularExpression) {
            working.replaceSubrange(existing, with: styleBlock)
        } else if let headEnd = working.range(of: "</head>", options: .caseInsensitive) {
            working.insert(contentsOf: styleBlock + "\n", at: headEnd.lowerBound)
        } else if let bodyStart = working.range(of: "<body", options: .caseInsensitive) {
            // Model omitted <head>: synthesize one before <body>.
            let synthesized = "<head>\n\(styleBlock)\n</head>\n"
            working.insert(contentsOf: synthesized, at: bodyStart.lowerBound)
        } else {
            // No recognizable structure — prepend so at least the variables are present.
            working = styleBlock + "\n" + working
        }

        // Inject (or refresh) the Tailwind config script. The script body is
        // theme-independent — it only references CSS variable names — so this
        // is purely an idempotent presence check. Only meaningful when a head
        // exists (the script needs `window.tailwind` from the CDN tag).
        let existingConfigPattern = #"<script id="\#(tailwindConfigScriptID)">[\s\S]*?</script>"#
        if let existing = working.range(of: existingConfigPattern, options: .regularExpression) {
            working.replaceSubrange(existing, with: configBlock)
        } else if let headEnd = working.range(of: "</head>", options: .caseInsensitive) {
            working.insert(contentsOf: configBlock + "\n", at: headEnd.lowerBound)
        }

        return setDarkClassOnHTMLTag(in: working, isDark: theme.isDark)
    }

    /// Splices the chosen icon library's CDN tags (and matching body-end init
    /// script) into model-generated HTML. Works the same way as `injectTheme`:
    /// a wrapper `<div id="sketch-icon-library">` block is inserted into
    /// `<head>` and a `<script id="sketch-icon-library-init">` is inserted
    /// just before `</body>`. Both are matched on the next call so switching
    /// libraries (or re-rendering the same one) replaces rather than stacks.
    ///
    /// Passing `.none` strips any previously-injected blocks but inserts none.
    /// Heroicons and Carbon are also `.none`-equivalent here because their
    /// icons are emitted as inline SVG by the model — no runtime needed.
    static func injectIconLibrary(into html: String, library: IconLibrary) -> String {
        let cleared = removeInjectedIconLibrary(from: html)
        guard library.integrationKind != .none && library.integrationKind != .inlineSVG else {
            return cleared
        }
        return appendIconLibraryBlocks(to: cleared, library: library)
    }

    private static func removeInjectedIconLibrary(from html: String) -> String {
        var working = html
        let headPattern = #"<div id="\#(iconLibraryContainerID)"[\s\S]*?</div>\s*"#
        if let range = working.range(of: headPattern, options: .regularExpression) {
            working.replaceSubrange(range, with: "")
        }
        let scriptPattern = #"<script id="\#(iconLibraryInitScriptID)"[\s\S]*?</script>\s*"#
        if let range = working.range(of: scriptPattern, options: .regularExpression) {
            working.replaceSubrange(range, with: "")
        }
        return working
    }

    private static func appendIconLibraryBlocks(to html: String, library: IconLibrary) -> String {
        let headBlock = """
        <div id="\(iconLibraryContainerID)" style="display:none">\(library.headTags)</div>
        """

        var working = html
        if let headEnd = working.range(of: "</head>", options: .caseInsensitive) {
            working.insert(contentsOf: headBlock + "\n", at: headEnd.lowerBound)
        } else if let bodyStart = working.range(of: "<body", options: .caseInsensitive) {
            let synthesized = "<head>\n\(headBlock)\n</head>\n"
            working.insert(contentsOf: synthesized, at: bodyStart.lowerBound)
        } else {
            working = headBlock + "\n" + working
        }

        if let raw = library.initScript {
            let initBlock = raw.replacingOccurrences(
                of: "<script>",
                with: #"<script id="\#(iconLibraryInitScriptID)">"#
            )
            if let bodyEnd = working.range(of: "</body>", options: .caseInsensitive) {
                working.insert(contentsOf: initBlock + "\n", at: bodyEnd.lowerBound)
            } else {
                working += "\n" + initBlock
            }
        }

        return working
    }

    /// Adds or removes a `dark` class on the `<html>` opening tag. Preserves
    /// other classes and other attributes (e.g. `lang`).
    private static func setDarkClassOnHTMLTag(in html: String, isDark: Bool) -> String {
        guard let tagRange = html.range(of: #"<html\b[^>]*>"#, options: .regularExpression) else {
            return html
        }
        let original = String(html[tagRange])
        var result = html
        result.replaceSubrange(tagRange, with: rewriteHTMLTagDarkClass(original, isDark: isDark))
        return result
    }

    private static func rewriteHTMLTagDarkClass(_ tag: String, isDark: Bool) -> String {
        if let classRange = tag.range(of: #"class="[^"]*""#, options: .regularExpression) {
            let attr = String(tag[classRange])
            // attr looks like `class="foo bar"` — strip leading 7 + trailing 1 chars to get value.
            let value = attr.dropFirst(7).dropLast()
            var classes = value
                .split(separator: " ")
                .map(String.init)
                .filter { !$0.isEmpty && $0 != "dark" }
            if isDark { classes.append("dark") }

            let replacement = classes.isEmpty ? "" : "class=\"\(classes.joined(separator: " "))\""
            var rewritten = tag
            rewritten.replaceSubrange(classRange, with: replacement)
            return rewritten
                .replacingOccurrences(of: "  ", with: " ")
                .replacingOccurrences(of: " >", with: ">")
        }

        guard isDark else { return tag }
        // No existing class attribute — insert one before the closing `>`.
        guard let closing = tag.lastIndex(of: ">") else { return tag }
        var rewritten = tag
        rewritten.insert(contentsOf: " class=\"dark\"", at: closing)
        return rewritten
    }

    // MARK: - Private Fragments

    /// Wraps an icon library's `headTags` in the same idempotency wrapper
    /// `injectIconLibrary(into:library:)` produces, so HTML built via
    /// `buildPreviewHTML` and HTML refined through `injectIconLibrary` end up
    /// matching the same regex on the *next* re-injection.
    private static func iconLibraryHeadBlock(for library: IconLibrary) -> String {
        let tags = library.headTags
        guard !tags.isEmpty else { return "" }
        return #"<div id="\#(iconLibraryContainerID)" style="display:none">\#(tags)</div>"#
    }

    /// Same idea for the body-end init script (Lucide's `createIcons()` call).
    private static func iconLibraryInitBlock(for library: IconLibrary) -> String {
        guard let raw = library.initScript else { return "" }
        return raw.replacingOccurrences(
            of: "<script>",
            with: #"<script id="\#(iconLibraryInitScriptID)">"#
        )
    }

    /// Renders the `:root` token block plus the `!important` overrides that
    /// make the theme toggle visible across model-generated HTML. The leading
    /// indent keeps the output readable when embedded in a larger `<style>`
    /// block.
    ///
    /// Why the body rule isn't enough: the prompt asks Gemini to use shadcn
    /// arbitrary-value classes (`bg-[hsl(var(--background))]`), but in practice
    /// it still emits raw Tailwind utilities — `<body class="bg-white …">`,
    /// `<div class="min-h-screen bg-gray-50">`, `<p class="text-gray-600">`.
    /// Class selectors (specificity 0,0,1,0) beat a plain `body {…}` rule
    /// (0,0,0,1), and a full-bleed wrapper div paints right over a themed
    /// body, so toggling base color or Light↔Dark looks like nothing happens.
    ///
    /// We address both: the body itself is forced via `!important`, AND the
    /// most common "neutral" Tailwind utilities (white/black and the
    /// gray/slate/zinc/neutral/stone scales used for surfaces, text, and
    /// borders) are remapped to the corresponding shadcn token. Accent
    /// utilities (`bg-blue-600`, etc.) are deliberately left alone — those
    /// stay as accents regardless of theme.
    private static func themeCSS(for theme: ShadcnTheme) -> String {
        let indented = theme.cssTokens()
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    " + $0 }
            .joined(separator: "\n")
        return """
        :root {
        \(indented)
        }
        body {
            background-color: hsl(var(--background)) !important;
            color: hsl(var(--foreground)) !important;
        }
        \(neutralUtilityOverridesCSS)
        """
    }

    /// `!important` overrides that pin the most common neutral Tailwind
    /// utilities to shadcn theme tokens. Selectors are theme-independent
    /// because they reference CSS variables that the `:root` block (which is
    /// regenerated on every theme switch) supplies. Listed shades cover the
    /// surfaces, body text, muted text, and borders Gemini actually emits;
    /// uncommon middle shades (300, 400 for bg; 200, 300 for text) are
    /// deliberately omitted so accent-tinted neutrals don't get coerced.
    private static let neutralUtilityOverridesCSS = """
    /* --- Page surfaces (light) --- */
    .bg-white,
    .bg-gray-50, .bg-gray-100,
    .bg-slate-50, .bg-slate-100,
    .bg-zinc-50, .bg-zinc-100,
    .bg-neutral-50, .bg-neutral-100,
    .bg-stone-50, .bg-stone-100 {
        background-color: hsl(var(--background)) !important;
    }
    /* --- Subtle surfaces (cards / muted) --- */
    .bg-gray-200, .bg-slate-200, .bg-zinc-200, .bg-neutral-200, .bg-stone-200 {
        background-color: hsl(var(--muted)) !important;
    }
    /* --- Inverted surfaces (footers / dark buttons) --- */
    .bg-black,
    .bg-gray-800, .bg-gray-900, .bg-gray-950,
    .bg-slate-800, .bg-slate-900, .bg-slate-950,
    .bg-zinc-800, .bg-zinc-900, .bg-zinc-950,
    .bg-neutral-800, .bg-neutral-900, .bg-neutral-950,
    .bg-stone-800, .bg-stone-900, .bg-stone-950 {
        background-color: hsl(var(--foreground)) !important;
    }
    /* --- Body text --- */
    .text-black,
    .text-gray-800, .text-gray-900, .text-gray-950,
    .text-slate-800, .text-slate-900, .text-slate-950,
    .text-zinc-800, .text-zinc-900, .text-zinc-950,
    .text-neutral-800, .text-neutral-900, .text-neutral-950,
    .text-stone-800, .text-stone-900, .text-stone-950 {
        color: hsl(var(--foreground)) !important;
    }
    /* --- Muted / secondary text --- */
    .text-gray-400, .text-gray-500, .text-gray-600, .text-gray-700,
    .text-slate-400, .text-slate-500, .text-slate-600, .text-slate-700,
    .text-zinc-400, .text-zinc-500, .text-zinc-600, .text-zinc-700,
    .text-neutral-400, .text-neutral-500, .text-neutral-600, .text-neutral-700,
    .text-stone-400, .text-stone-500, .text-stone-600, .text-stone-700 {
        color: hsl(var(--muted-foreground)) !important;
    }
    /* --- Text on inverted surfaces --- */
    .text-white,
    .text-gray-50, .text-gray-100,
    .text-slate-50, .text-slate-100,
    .text-zinc-50, .text-zinc-100,
    .text-neutral-50, .text-neutral-100,
    .text-stone-50, .text-stone-100 {
        color: hsl(var(--background)) !important;
    }
    /* --- Borders / dividers --- */
    .border-gray-100, .border-gray-200, .border-gray-300,
    .border-slate-100, .border-slate-200, .border-slate-300,
    .border-zinc-100, .border-zinc-200, .border-zinc-300,
    .border-neutral-100, .border-neutral-200, .border-neutral-300,
    .border-stone-100, .border-stone-200, .border-stone-300 {
        border-color: hsl(var(--border)) !important;
    }
    /* Plain `border` (no color suffix) defaults to gray-200 in Tailwind. */
    .divide-gray-200 > :not([hidden]) ~ :not([hidden]),
    .divide-slate-200 > :not([hidden]) ~ :not([hidden]),
    .divide-zinc-200 > :not([hidden]) ~ :not([hidden]),
    .divide-neutral-200 > :not([hidden]) ~ :not([hidden]),
    .divide-stone-200 > :not([hidden]) ~ :not([hidden]) {
        border-color: hsl(var(--border)) !important;
    }
    """

    /// Configures the Tailwind Play CDN once it has loaded. Two things matter:
    ///
    /// 1. `darkMode: 'class'` — by default the CDN uses `'media'`, so any
    ///    `dark:` utility the model emits only fires on the iPad's OS-level
    ///    appearance. Flipping to `'class'` makes those utilities follow the
    ///    `dark` class we toggle on `<html>` in `setDarkClassOnHTMLTag`, so
    ///    the user-chosen appearance actually drives them.
    /// 2. Named shadcn colors — registering `background`, `primary`, `card`,
    ///    etc. as Tailwind colors lets the model write `bg-primary` /
    ///    `text-card-foreground` instead of the verbose arbitrary-value
    ///    classes (`bg-[hsl(var(--primary))]`). Both forms work and theme
    ///    correctly; the named form is more idiomatic and what real shadcn
    ///    codebases use.
    ///
    /// The script is guarded by `if (window.tailwind)` so it's a no-op when
    /// the model omitted the CDN tag (e.g. offline export).
    private static let tailwindConfigJS = """
    if (window.tailwind) {
        tailwind.config = {
            darkMode: 'class',
            theme: {
                extend: {
                    colors: {
                        border: 'hsl(var(--border))',
                        input: 'hsl(var(--input))',
                        ring: 'hsl(var(--ring))',
                        background: 'hsl(var(--background))',
                        foreground: 'hsl(var(--foreground))',
                        primary: {
                            DEFAULT: 'hsl(var(--primary))',
                            foreground: 'hsl(var(--primary-foreground))'
                        },
                        secondary: {
                            DEFAULT: 'hsl(var(--secondary))',
                            foreground: 'hsl(var(--secondary-foreground))'
                        },
                        destructive: {
                            DEFAULT: 'hsl(var(--destructive))',
                            foreground: 'hsl(var(--destructive-foreground))'
                        },
                        muted: {
                            DEFAULT: 'hsl(var(--muted))',
                            foreground: 'hsl(var(--muted-foreground))'
                        },
                        accent: {
                            DEFAULT: 'hsl(var(--accent))',
                            foreground: 'hsl(var(--accent-foreground))'
                        },
                        popover: {
                            DEFAULT: 'hsl(var(--popover))',
                            foreground: 'hsl(var(--popover-foreground))'
                        },
                        card: {
                            DEFAULT: 'hsl(var(--card))',
                            foreground: 'hsl(var(--card-foreground))'
                        }
                    },
                    borderRadius: {
                        lg: 'var(--radius)',
                        md: 'calc(var(--radius) - 2px)',
                        sm: 'calc(var(--radius) - 4px)'
                    }
                }
            }
        };
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
