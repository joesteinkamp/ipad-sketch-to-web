# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

iPadOS app (Swift/SwiftUI, iOS 17+) that lets users sketch UI wireframes with Apple Pencil and converts them into coded websites using shadcn/ui components via Google's Gemini vision API. System frameworks only (PencilKit, WebKit, SwiftData, Security) plus a single SPM dependency: [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (MIT) used by the design-system zip importer.

## Architecture

**Core flow:** Draw on PencilKit canvas → export as PNG → stream to Gemini vision API with component catalog prompt → parse JSON response → render interactive HTML preview in WKWebView / display React code → annotate and refine iteratively.

### Key Layers

- **App/** — Entry point (`SketchToWebApp`), root layout (`ContentView` with `NavigationSplitView`), and `AppState` (ObservableObject holding conversion state, streaming text, generation history, refinement state)
- **Models/** — `Project` (SwiftData @Model with folder/tags/generations relationships), `ProjectFolder`, `Generation` (persisted version history), `GeneratedCode` (Codable struct with htmlPreview + reactCode), `ComponentDefinition` (loaded from bundled JSON catalog), `DesignSystem` (singleton SwiftData @Model storing company blurb, DESIGN.md content, source URL, zip extract, fonts/assets) + `DesignSystemSnapshot` (Sendable plain-struct copy used by pipelines)
- **Views/Canvas/** — `PencilCanvasView` (UIViewRepresentable bridging PKCanvasView), `CanvasView` (main drawing screen with auto-save, auto-convert, drawing hints), `CanvasToolbar`, `TextToSketchSheet` (AI-generated wireframes from text descriptions), `TemplatePickerSheet` (pre-built layout starters), `DrawingHintOverlay` (real-time shape recognition badges)
- **Views/Preview/** — `AnnotatablePreviewView` (PencilKit overlay on WKWebView for iterative refinement), `ResponsivePreviewView` (phone/tablet/desktop device frames), `WebPreviewView`, `CodePreviewView`, `PreviewContainerView` (tabbed container with version history navigation), `GenerationHistoryView` (timeline of all generations per project)
- **Views/Projects/** — `ProjectListView` (sectioned by folders, searchable, drag-and-drop), `ProjectDetailView` (with tags), `TagEditorView` (chip-based tag editor with autocomplete)
- **Services/AI/** — `GeminiClient` (URLSession HTTP client with streaming SSE support), `SketchAnalysisPrompt`, `CodeGenerationResponse` (JSON parser with regex fallback), `AIConversionPipeline` (orchestrator with streaming), `RefinementPipeline` (iterative annotation-based refinement), `DesignSystemImporter` (raw-URL fetch for GitHub/GitLab/Bitbucket + zip extraction via ZIPFoundation + sandbox file persistence)
- **Services/Drawing/** — `DrawingExporter`, `SketchTemplates` (5 pre-built wireframe templates), `StrokeAnalyzer` (shape recognition for hint badges)
- **Services/Storage/** — `KeychainHelper` (API key in Keychain), `ProjectStore` (SwiftData operations)

### UIKit Bridges

Four components use UIViewRepresentable:
1. `PencilCanvasView` — wraps `PKCanvasView`; Coordinator holds strong ref to `PKToolPicker`; uses NotificationCenter for undo/redo
2. `WebPreviewView` — wraps `WKWebView`; tracks last-loaded content to avoid reloads
3. `AnnotationCanvasView` — transparent PKCanvasView overlay with red pen for preview annotations
4. `SnapshotableWebPreviewView` — non-interactive WKWebView exposing ref for screenshot capture

### Streaming & Auto-Convert

`GeminiClient.streamMessage()` uses the `streamGenerateContent?alt=sse` endpoint. SSE chunks are parsed and accumulated, yielding partial text via `AsyncThrowingStream`. `AppState.streamingText` updates in real-time. Auto-convert triggers 3 seconds after the pencil lifts (configurable via `@AppStorage("autoConvertEnabled")`).

### Iterative Refinement

`AnnotatablePreviewView` layers a transparent PencilKit canvas (red pen) over the web preview. "Refine" captures a composite screenshot (WKWebView snapshot + PencilKit strokes) and sends it to `RefinementPipeline` with the current code as context. Results push onto `AppState.generationHistory` with back/forward navigation.

### API Key Storage

Gemini API keys stored in iOS Keychain via `KeychainHelper`, NOT UserDefaults. Read from Keychain on each conversion. Model selection in `@AppStorage("selectedModel")`. Default: `gemini-3.1-pro-preview`.

### SwiftData Schema

Three models registered in `modelContainer`: `Project`, `ProjectFolder`, `Generation`. Projects have optional folder relationship, tags array, and cascading generations relationship.

## Build & Run

This is a Swift/Xcode project. To build:
1. Open in Xcode 15+
2. Set deployment target to iPadOS 17.0
3. Add system frameworks: PencilKit, WebKit, SwiftData, Security
4. Build and run on iPad (physical device recommended for Apple Pencil testing)

Testing requires a Gemini API key (from aistudio.google.com) entered in the Settings sheet.

## Tests

Tests are in `SketchToWebTests/`:
- `CodeGenerationResponseTests` — JSON parsing, markdown fence handling, error cases
- `HTMLTemplateEngineTests` — template generation, CSS variable presence, offline mode

Run tests via Xcode's Test navigator or `xcodebuild test`.

## Resources

- `Resources/component-catalog.json` — 20 shadcn/ui component definitions with sketch patterns, import paths, and usage examples. This drives the prompt system.
- `Resources/preview-template.html` — standalone HTML template with Tailwind CDN and shadcn/ui CSS variables + component styles.

## User Preferences (AppStorage keys)

- `selectedModel` — Gemini model ID
- `autoConvertEnabled` — auto-convert after 3s drawing pause
- `showDrawingHints` — shape recognition badge overlay
