# Static Review — `claude/extensive-app-testing-OQD1h` vs `main`

Recent merged work (PRs #13–#17 plus the design-system QA pass) introduced ~7,500 lines across the AppState refactor (`AppError`, `GenerationHistory`), the design-system import/synthesis pipeline, the shadcn theme catalog, and a much-expanded refinement view. This review focuses on bugs that could cause data loss, silent failures, or user-facing crashes — not stylistic concerns.

Each finding cites a `path:line` (verified against the working tree at HEAD = `0761cfc`) and proposes a fix without making it.

> **Note on scope.** `AppState` is `@MainActor`, so the `Task` closures launched from `convertDrawing()` and `refineResult()` inherit main-actor isolation. That eliminates several races a casual read might suspect; the findings below are limited to issues that survive that isolation.

---

## High (5 findings)

### [H-1] `WKWebView.takeSnapshot` errors are silently swallowed during refinement

**File:** `SketchToWeb/Views/Preview/AnnotatablePreviewView.swift:162-163`
**Finding:** `webView.takeSnapshot(with:) { image, error in guard let webImage = image else { return } … }` discards the `error` parameter and silently aborts. If the snapshot fails (low memory, off-screen view, WebKit crash), the user taps **Refine** and nothing happens — no spinner ends, no error appears. They'll think the model gave a bad result and try again.
**Suggested fix:** Capture the `Error`, hop back to the main actor, and surface it via `appState.conversionError = …` so the existing alert path picks it up. Reset any "refining" UI state in the same path.

### [H-2] `KeychainHelper.saveOAuthTokens` returns `Bool`; callers ignore it

**File:** `SketchToWeb/Services/Auth/FigmaOAuth.swift:82` (call site); `SketchToWeb/Services/Storage/KeychainHelper.swift:127` (returns `Bool`)
**Finding:** `connect()` does `KeychainHelper.saveOAuthTokens(bundle, for: destination)` with no `if !saved` check. If the keychain write fails (device locked, ACL conflict, profile policy), `connect()` returns the access token in memory and reports success, but the next call to `currentAccessToken()` calls `KeychainHelper.loadOAuthTokens` and gets `nil` → throws `noStoredToken`. The user sees "Not signed in" immediately after appearing to sign in.
**Suggested fix:** Either change `saveOAuthTokens` to throw, or surface the `Bool` result in `connect()` and throw `OAuthError.refreshFailed("Could not persist token")` (or a new case) when it returns `false`.

### [H-3] `WKWebView` has no navigation/error delegate in `AnnotatablePreviewView`

**File:** `SketchToWeb/Views/Preview/AnnotatablePreviewView.swift:430` (and the surrounding `SnapshotableWebPreviewView`)
**Finding:** `webView.loadHTMLString(rendered, baseURL: nil)` is invoked without setting `webView.navigationDelegate`. If the rendered HTML throws a JS error, references a missing CDN (Tailwind), or is malformed, the user sees a blank webview with no indication that something went wrong. The conversion pipeline already considers itself successful at this point.
**Suggested fix:** Implement a lightweight `WKNavigationDelegate` that captures `didFailProvisionalNavigation` / `didFail` / `webViewWebContentProcessDidTerminate` and routes them to a published error string the parent view can display.

### [H-4] Long-running tasks in `DesignSystemSetupView` aren't cancelled on dismiss

**File:** `SketchToWeb/Views/Settings/DesignSystemSetupView.swift:265, 436, 497`
**Finding:** Tasks are launched inline (`Task { await fetchSourceURL() }`, `Task { … import zip … }`, `Task { await synthesize() }`) without being stored or cancelled when the sheet is dismissed. While the SwiftData model keeps the writes safe (the model isn't deallocated), a synthesis call that's been issued can still take 30–60s to complete and consumes Gemini quota the user can no longer see. If the user reopens the sheet, two synthesis calls can be in flight at once and clobber each other on completion.
**Suggested fix:** Hold each task in a `@State var activeTask: Task<Void, Never>?`, cancel it on `.onDisappear`, and gate re-entry to `synthesize()` so the sheet can't queue a second call while one is in flight.

### [H-5] `AnnotationMode` transitions don't reset the active comment editor

**File:** `SketchToWeb/Views/Preview/AnnotatablePreviewView.swift:236-240` (mode picker), comment editing state lives in the same view
**Finding:** The Draw / Comment segmented picker writes directly to `mode`. If the user is mid-typing on a comment pin (`editingCommentID != nil`) and switches to Draw, the keyboard stays up because nothing clears the focus state — and the next pin tap can re-open the field on top of an existing one. Cleanup currently only runs when calling `exitAnnotate()`.
**Suggested fix:** Use a `.onChange(of: mode)` modifier (or property observer) that resets `editingCommentID` and dismisses the keyboard whenever the mode changes, regardless of the new value.

---

## Medium (5 findings)

### [M-1] Default Gemini model string repeated in three call sites

**File:** `SketchToWeb/App/AppState.swift:75, 117, 188`
**Finding:** `let model = UserDefaults.standard.string(forKey: "selectedModel") ?? "gemini-3.1-pro-preview"` appears verbatim three times (in `convertDrawing`, `refineResult`, and one more path). The `CLAUDE.md` already documents the default, so updating the model means changing all three plus the doc.
**Suggested fix:** Extract a `static let defaultGeminiModel = "gemini-3.1-pro-preview"` (or a `selectedModel(forKey:)` helper) and reference it from all call sites.

### [M-2] `DesignSystemSnapshot.Equatable` doesn't normalize file ordering, but the fingerprint does

**File:** `SketchToWeb/Models/DesignSystem.swift:179-205` (snapshot struct, auto-synthesised `Equatable`); `:269, :273` (fingerprint sorts file lists)
**Finding:** `DesignSystemSnapshot` uses auto-synthesised `Equatable` over `fontFileNames` and `assetFileNames` arrays where order matters. The fingerprint computation sorts these lists before hashing. Two snapshots that produce the same fingerprint can nonetheless compare unequal if the underlying `fontFilePaths` were inserted in different orders. Today this only bites if a caller compares two snapshots directly (currently rare), but the asymmetry is a footgun.
**Suggested fix:** Either custom-`==` the snapshot to sort file lists before comparison, or sort them at construction time inside `DesignSystem.snapshot()` (lines 168–169) so both `==` and the fingerprint see the same canonical order.

### [M-3] No size or time cap on `DesignSystemSynthesizer` Gemini call

**File:** `SketchToWeb/Services/AI/DesignSystemSynthesizer.swift:39-42`
**Finding:** `synthesize` calls `client.sendTextMessage(...)` and accumulates the full response string with no upper bound. Each input source is already truncated to 10,000 chars (`synthesisInputLimit`, line 123), but the output isn't capped. A model that goes off-script could return tens of MBs that get stored in `synthesizedMarkdown` and re-sent on every conversion. There's also no per-call timeout.
**Suggested fix:** Cap the response at, say, 50 KB after streaming and truncate with a `[truncated]` marker; enforce a 60s overall deadline via `Task` timeout / `withThrowingTaskGroup`.

### [M-4] `DesignPresetGalleryView` loads the catalog synchronously during `@State` init

**File:** `SketchToWeb/Views/Settings/DesignPresetGalleryView.swift:26`
**Finding:** `@State private var presets: [DesignPreset] = DesignPreset.loadCatalog()` runs `Bundle.main.url(...)` + `Data(contentsOf:)` + JSON decode on the main thread when the view is first constructed. The catalog is small (3 KB today) so the cost is currently negligible, but the pattern is fragile — if the catalog grows or moves to disk, sheet open will jank. Also, `loadCatalog()` swallows errors silently, so a malformed JSON would show an empty gallery with no diagnostic.
**Suggested fix:** Initialise `presets` to `[]` and load it inside a `.task` modifier on the gallery; surface a small "couldn't load presets" error label when the result is empty.

### [M-5] `FigmaMCPClient` doesn't sanitize the bearer token before stamping it on the header

**File:** `SketchToWeb/Services/AI/FigmaMCPClient.swift:136`
**Finding:** `request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")` directly interpolates whatever the token provider returns. A corrupted keychain entry containing CR/LF could split the request line. The risk is low (Apple's URL loading system tends to reject these), but the defensive habit is cheap.
**Suggested fix:** Trim whitespace and reject tokens containing newlines/control characters before setting the header. Alternatively, assert in DEBUG builds.

---

## Notes — claims considered and rejected

These were on the candidate list but didn't survive verification against the source; documenting so the next reviewer doesn't re-investigate them:

- **"API key never validated for emptiness."** Both `convertDrawing` (`AppState.swift:72`) and `refineResult` (`AppState.swift:114`) explicitly guard `!apiKey.isEmpty` before constructing pipelines.
- **"Race on `generationHistory` / `generationHistoryIndex`."** `AppState` is annotated `@MainActor` (line 5), so all reads/writes — including those inside `Task` closures and computed properties — run on the main actor. Out-of-bounds slip is not possible from the current call graph.
- **"Race on `designSystemSnapshot`."** Same reason: it's `@Published` on a `@MainActor` class and is only read from `Task` closures spawned by main-actor methods.
- **"PKCE code_verifier never verified."** PKCE places verification on the *server* side at the `/token` endpoint (`exchangeCodeForToken` at `FigmaOAuth.swift:216-233` sends `code_verifier`). The client doesn't and shouldn't re-verify.

---

## Triage suggestion

Recommended fix order: **H-1 → H-2 → H-3** as a single PR (all preview/auth user-visible failures), then **H-4 → H-5** as a follow-up (refinement + setup-view polish). The Medium findings can ride along opportunistically; **M-3** is the one to prioritise if synthesis is exposed to untrusted prompts.

| Finding | Status | Owner | PR |
|---|---|---|---|
| H-1 | ☐ |  |  |
| H-2 | ☐ |  |  |
| H-3 | ☐ |  |  |
| H-4 | ☐ |  |  |
| H-5 | ☐ |  |  |
| M-1 | ☐ |  |  |
| M-2 | ☐ |  |  |
| M-3 | ☐ |  |  |
| M-4 | ☐ |  |  |
| M-5 | ☐ |  |  |
