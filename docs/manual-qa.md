# Manual QA Checklist — Sketch-to-Web (iPad)

Run this on a physical iPad with Apple Pencil (recommended) or the iPad simulator. Tick each box after observing the expected outcome. For any failure, capture: screenshot/video, exact reproduction steps, and the build's git SHA.

**Setup (one-time)**

- [ ] Build & run on iPadOS 17+
- [ ] Open Settings sheet → enter a valid Gemini API key (saved to Keychain)
- [ ] Confirm `selectedModel` is set (default: `gemini-3.1-pro-preview`)
- [ ] Reset SwiftData if testing first-launch flows: delete app from device, reinstall

---

## 1. Onboarding & Settings

| # | Steps | Expected | Pass |
|---|---|---|---|
| 1.1 | Cold-launch the app (no API key set) | Empty state visible; Settings sheet reachable from sidebar/toolbar | ☐ |
| 1.2 | Open Settings → enter API key → Save | Sheet dismisses; key persists across relaunch | ☐ |
| 1.3 | Force-quit & relaunch | API key still loaded (read from Keychain, not UserDefaults) | ☐ |
| 1.4 | Settings → Clear API key | Conversion attempts now show "Missing API key" error | ☐ |
| 1.5 | Settings → switch model picker (e.g. `gemini-2.5-flash`) | Subsequent conversion uses the new model | ☐ |
| 1.6 | Settings → toggle Auto-convert off | Drawing pause no longer triggers conversion | ☐ |
| 1.7 | Settings → toggle Drawing hints | Shape recognition badges appear/disappear during drawing | ☐ |
| 1.8 | Theme toggle: cycle 5 base colors × {light, dark, system} | Preview re-renders with matching CSS vars; no flicker | ☐ |
| 1.9 | Settings persistence | Every toggle survives a force-quit | ☐ |

## 2. Canvas & Pencil Input

| # | Steps | Expected | Pass |
|---|---|---|---|
| 2.1 | Draw with Apple Pencil | Strokes render at 60+ Hz; no input lag | ☐ |
| 2.2 | Draw with finger | Tool picker indicates fallback; strokes still render | ☐ |
| 2.3 | Tool picker → switch to eraser → erase a stroke | Stroke removed; undo restores it | ☐ |
| 2.4 | Tool picker → ruler → straight stroke along ruler | Ruler edge produces a perfectly straight stroke | ☐ |
| 2.5 | Undo (3-finger swipe or button) | Last stroke removed | ☐ |
| 2.6 | Redo | Stroke restored | ☐ |
| 2.7 | Drawing hint overlay (if enabled) | Recognized shapes show badge near top-right of bounds | ☐ |
| 2.8 | Switch project mid-draw | Current project saves; new project canvas is blank | ☐ |
| 2.9 | Layout mode toggle: split / canvas-only / preview-only | Layout transitions smoothly; canvas remains usable in canvas-only | ☐ |
| 2.10 | Rotate iPad mid-draw | Canvas resizes; existing strokes scale or reposition correctly | ☐ |

## 3. Templates & Text-to-Sketch

| # | Steps | Expected | Pass |
|---|---|---|---|
| 3.1 | Templates sheet → Login Form | 21 strokes appear centered on the canvas | ☐ |
| 3.2 | Templates → Dashboard | Top navbar + sidebar + 2×2 stat cards render | ☐ |
| 3.3 | Templates → Landing Page | Navbar + hero + 3 feature cards + footer | ☐ |
| 3.4 | Templates → Settings Page | Top bar + left nav + right form area | ☐ |
| 3.5 | Templates → Pricing Page | 3 pricing tier cards with 5 features each | ☐ |
| 3.6 | Apply template on a non-empty canvas | Strokes append (or overwrite, per design); no crash | ☐ |
| 3.7 | Text-to-Sketch sheet → "Login screen with social auth" | Strokes generated and inserted | ☐ |
| 3.8 | Text-to-Sketch with no API key | Graceful error message | ☐ |
| 3.9 | Text-to-Sketch in airplane mode | Network error surfaced; canvas unchanged | ☐ |

## 4. Auto-Convert & Streaming Preview

| # | Steps | Expected | Pass |
|---|---|---|---|
| 4.1 | Draw a wireframe → wait 3s | Conversion fires automatically | ☐ |
| 4.2 | Continue drawing during the 3s window | Timer resets; no premature convert | ☐ |
| 4.3 | Disable auto-convert → manually tap Convert | One conversion fires immediately | ☐ |
| 4.4 | Streaming preview during conversion | Partial HTML renders progressively | ☐ |
| 4.5 | Cancel mid-stream | Previous render preserved; no half-baked HTML | ☐ |
| 4.6 | Convert empty canvas | Graceful error or no-op (don't send blank PNG) | ☐ |
| 4.7 | Convert with malformed Gemini JSON response | `CodeGenerationResponse` regex fallback engages; preview still renders | ☐ |

## 5. Refinement Loop

Pre-condition: a generation exists in the preview.

| # | Steps | Expected | Pass |
|---|---|---|---|
| 5.1 | Tap "Annotate" entry button | Toolbar appears: Draw / Comment / Refine / Overflow / X | ☐ |
| 5.2 | Draw mode → freehand strokes | Red strokes overlay the web preview | ☐ |
| 5.3 | Comment mode → tap on preview | Numbered pin appears; inline text field opens | ☐ |
| 5.4 | Type comment → switch to Draw mode | Pin and text persist | ☐ |
| 5.5 | Add 3 pins → switch to Draw → switch back | All 3 pins still visible with their numbers in order | ☐ |
| 5.6 | Tap Refine | Composite screenshot sent (web + strokes + pins); new generation appended to history | ☐ |
| 5.7 | Overflow → Clear all | Strokes and pins removed | ☐ |
| 5.8 | Tap X | Toolbar collapses to Annotate entry button | ☐ |

## 6. Generation History

| # | Steps | Expected | Pass |
|---|---|---|---|
| 6.1 | After 3+ generations, tap Back | Preview shows previous generation; version label updates | ☐ |
| 6.2 | Tap Forward | Returns to next generation | ☐ |
| 6.3 | Refine from older generation | New branch appended to history (or replaces forward, per design) | ☐ |
| 6.4 | Force-quit & relaunch | Full history persisted | ☐ |

## 7. Projects & Folders

| # | Steps | Expected | Pass |
|---|---|---|---|
| 7.1 | Create new project | Appears in sidebar; can rename inline | ☐ |
| 7.2 | Drag project into a folder | Folder hierarchy updates; SwiftData persists | ☐ |
| 7.3 | Delete project | Confirmation prompt; project removed | ☐ |
| 7.4 | Add tag → autocomplete | Existing tags suggested; chip added | ☐ |
| 7.5 | Search projects by name | Sidebar filters in real time | ☐ |
| 7.6 | Search projects by tag | Tag-only matches surface | ☐ |
| 7.7 | Project detail view | Name, tags, folder, generation count visible | ☐ |
| 7.8 | Rename folder | All children stay attached | ☐ |
| 7.9 | Delete non-empty folder | Confirmation prompt; children handled per design | ☐ |

## 8. Design System

### 8a. Import sources

| # | Steps | Expected | Pass |
|---|---|---|---|
| 8a.1 | Import from raw GitHub URL (`https://raw.githubusercontent.com/.../DESIGN.md`) | Body fetched; preview shows blurb | ☐ |
| 8a.2 | Import from GitHub HTML URL (`https://github.com/.../blob/.../DESIGN.md`) | Auto-rewritten to raw URL; body fetched | ☐ |
| 8a.3 | Import from GitLab URL | Raw rewrite + fetch succeed | ☐ |
| 8a.4 | Import from Bitbucket URL | Raw rewrite + fetch succeed | ☐ |
| 8a.5 | Import from `.zip` file | ZIPFoundation extracts; assets persisted to sandbox | ☐ |
| 8a.6 | Import a 404 URL | Clear error; existing design system preserved | ☐ |

### 8b. Presets & synthesis

| # | Steps | Expected | Pass |
|---|---|---|---|
| 8b.1 | Open getdesign.md preset picker | All entries from `design-presets.json` listed | ☐ |
| 8b.2 | Pick "Apple" preset | Blurb populates; DESIGN.md fetched lazily | ☐ |
| 8b.3 | Tap Synthesize button | New DESIGN.md produced from imported sources + presets | ☐ |
| 8b.4 | Per-project design override | Project's design system supersedes the global one in conversions | ☐ |
| 8b.5 | Clear design system | Conversions revert to default prompt | ☐ |
| 8b.6 | Long blurb (>2000 chars) | Synthesizer truncates or summarizes; no prompt-size errors | ☐ |

## 9. Theme Toggle (5 colors × 3 appearances = 15 paths)

For each combination, draw a quick sketch and convert. The preview's CSS variables should match the upstream shadcn/ui values for that base.

| Base | Light | Dark | System |
|---|---|---|---|
| slate | ☐ | ☐ | ☐ |
| gray | ☐ | ☐ | ☐ |
| zinc | ☐ | ☐ | ☐ |
| neutral | ☐ | ☐ | ☐ |
| stone | ☐ | ☐ | ☐ |

- [ ] Theme persists per project (switching projects loads that project's theme)
- [ ] System mode follows iPad's Dark Mode toggle in real time

## 10. Figma Export (optional — requires Figma OAuth setup)

| # | Steps | Expected | Pass |
|---|---|---|---|
| 10.1 | Settings → Connect Figma | Browser auth flow completes; tokens persisted to Keychain | ☐ |
| 10.2 | Export current generation | Figma file/page created or updated | ☐ |
| 10.3 | Disconnect Figma | Tokens cleared; subsequent export prompts re-auth | ☐ |
| 10.4 | Token expiry → auto-refresh | Stored refresh token used silently; no user prompt | ☐ |

## 11. Edge Cases & Regressions

| # | Steps | Expected | Pass |
|---|---|---|---|
| 11.1 | Convert with invalid API key | "Invalid API key" error shown; doesn't crash | ☐ |
| 11.2 | Convert in airplane mode | Network error surfaced; previous render preserved | ☐ |
| 11.3 | Gemini 5xx response | Server error message shown; retry button if applicable | ☐ |
| 11.4 | Gemini 429 rate limit | Retry-after honored; user notified | ☐ |
| 11.5 | Malformed JSON from Gemini (markdown-fenced) | Regex fallback in `CodeGenerationResponse` extracts code blocks | ☐ |
| 11.6 | 4096px-wide canvas | PNG export succeeds; conversion latency reasonable | ☐ |
| 11.7 | Tiny canvas (320×240) | Templates still render in-bounds | ☐ |
| 11.8 | Backgrounded mid-conversion | Conversion completes when foregrounded; UI consistent | ☐ |
| 11.9 | Low-memory warning during streaming | App doesn't crash; partial state recoverable | ☐ |
| 11.10 | Force-quit during refinement | History preserved; no orphaned annotation state on next open | ☐ |
| 11.11 | Delete project mid-conversion | Conversion cancels gracefully | ☐ |
| 11.12 | Apple Pencil double-tap (eraser/tool toggle) | Behavior matches system setting | ☐ |
| 11.13 | External keyboard shortcuts (⌘Z, ⌘⇧Z) | Undo/redo work in canvas | ☐ |
| 11.14 | Voice Control / Switch Control | Critical buttons reachable; accessibility labels present | ☐ |

## 12. Persistence & Crashes

| # | Steps | Expected | Pass |
|---|---|---|---|
| 12.1 | Force-quit with in-flight generation | On relaunch, AppState shows `.idle`, no orphaned spinner | ☐ |
| 12.2 | Force-quit with unsaved drawing | Drawing was auto-saved; restored on relaunch | ☐ |
| 12.3 | Delete & reinstall app | First-launch experience triggers; no leftover state | ☐ |
| 12.4 | Migrate from previous schema (if applicable) | SwiftData migration succeeds; existing projects load | ☐ |

---

## Triage Template

For each unchecked box, file an issue with:

```
**Section:** §X.Y
**Build:** <git SHA> on iPadOS <version>, <iPad model>
**Steps:** ...
**Actual:** ...
**Expected:** ...
**Repro rate:** N/M attempts
**Logs:** (Console.app filtered to "SketchToWeb")
```
