# TODO

---

## Drawing Tools

Improvements to make core drawing tools more accessible and polished in the canvas toolbar, rather than relying solely on Apple's system PKToolPicker.

**Key files:** `CanvasToolbar.swift`, `PencilCanvasView.swift`, `CanvasView.swift`, `AppState.swift`

---

## Undo / Redo

Undo and redo already work via NotificationCenter posts to PKCanvasView's built-in UndoManager. Improvements:

- [x] **Track undo/redo availability** — observe `NSUndoManagerDidUndoChange` / `NSUndoManagerDidRedoChange` / `NSUndoManagerDidCloseUndoGroup` notifications (or poll `canUndo`/`canRedo`) and expose as bindings so toolbar buttons show a disabled state when there's nothing to undo/redo
- [x] **Replace NotificationCenter with direct Coordinator calls** — instead of posting `.canvasUndoRequested` globally, expose `undo()`/`redo()` methods on the Coordinator and call them via a ref (e.g. a lightweight wrapper object passed as a binding), removing the loosely-coupled notification pattern

## Line Thickness

Currently hardcoded to width 3.0 in `PencilCanvasView.swift:29`.

- [x] **Add thickness state** — add a `@Published var penWidth: CGFloat` to AppState (or `@State` in CanvasView) with a sensible default (e.g. 3.0)
- [x] **Add thickness picker to toolbar** — add a compact UI element to CanvasToolbar (segmented control with thin/medium/thick presets, or a small slider popover) that writes to the thickness state
- [x] **Apply thickness in PencilCanvasView** — accept the thickness as a binding, and in `updateUIView` re-apply `PKInkingTool(.pen, color: .black, width: selectedWidth)` when the value changes

## Eraser

Currently only accessible through Apple's floating PKToolPicker UI.

- [x] **Add active tool state** — add an enum (`pen` / `eraser`) to AppState or CanvasView state to track the selected tool
- [x] **Add eraser toggle to toolbar** — add an eraser button (SF Symbol `eraser`) to CanvasToolbar that toggles the active tool; highlight it when eraser is active
- [x] **Apply tool in PencilCanvasView** — accept active tool as a binding, and in `updateUIView` set `canvasView.tool` to `PKEraserTool(.bitmap)` when eraser is selected or `PKInkingTool(...)` when pen is selected
- [x] **Coordinate with PKToolPicker** — if the user selects a tool from the system picker, sync the toolbar state back (observe `PKToolPickerObserver` delegate methods)

---

## High Priority — Error Handling & Data Safety

### Silent error swallowing in persistence layer

`ProjectStore.swift` catches save errors and only prints to console. `CanvasView.swift` silently drops corrupted drawing data. Users are never informed of data loss.

- [x] **Surface save errors to the user** — add a `@Published var lastSaveError: String?` to `ProjectStore` and display an alert or banner in the UI when a save fails
- [x] **Alert on drawing corruption** — in `CanvasView.loadDrawing()`, show a user-facing error when `PKDrawing(data:)` throws instead of silently falling back to an empty drawing

### Streaming race condition in GeminiClient

`GeminiClient.streamMessage()` creates a `Task` inside `AsyncThrowingStream` with no cancellation handler. If the stream consumer cancels, the Task keeps running and may yield after the continuation is finished.

- [x] **Add continuation termination handler** — use the `AsyncThrowingStream` `onTermination` closure to cancel the inner Task when the stream is cancelled

---

## Medium Priority — Concurrency & Performance

### Missing weak self in UIViewRepresentable bridges

`AnnotatablePreviewView.swift` captures `self` strongly in `DispatchQueue.main.async` blocks when setting `webViewRef` and `canvasViewRef`.

- [x] **Use `[weak self]` in async closures** — Investigated: `[weak self]` is not applicable to structs (UIViewRepresentable). The struct is captured by value, not reference, so there is no retain cycle. Original code is correct.

### No SwiftData index on Generation.createdAt

`GenerationHistoryView` sorts generations by `createdAt` but the field has no `@Index`, which will degrade with large histories.

- [x] **Add `@Index` to `Generation.createdAt`** in `Models/Generation.swift` — Note: SwiftData on iOS 17 does not have a declarative index annotation; SwiftData auto-indexes based on `@Query` sort descriptors. When upgrading to iOS 18+, use `#Index<Generation>([\.createdAt])`

### Inconsistent @Published in AppState

`canvasSize`, `currentDrawing`, and `currentProject` are plain `var` properties on `AppState`, bypassing SwiftUI's reactivity. Views that depend on these won't re-render on changes.

- [x] **Mark with `@Published`** — make `canvasSize`, `currentDrawing`, and `currentProject` `@Published` in `AppState.swift`

### Template previews regenerated every render

`TemplatePickerSheet.swift` calls `DrawingExporter.exportAsImage()` on every view body evaluation with no caching.

- [x] **Cache template preview images** — store generated `UIImage`s in a `@State` dictionary keyed by template name so they're only rendered once

### Syntax highlighting recomputed every render

`CodePreviewView.swift` builds an `AttributedString` with regex highlighting on every view update.

- [x] **Memoize highlighted code** — cache the `AttributedString` in `@State` and only recompute when the source code string changes (e.g. via `.onChange(of: code)`)

### Large drawingSnapshot in Generation model

`Generation.drawingSnapshot` stores raw PencilKit data that can be multi-MB per generation, bloating the SwiftData store.

- [x] **Compress snapshots** — gzip `drawingSnapshot` on write and decompress on read, or make the field optional and only store for the most recent N generations

---

## Low Priority — Code Quality

### Magic numbers

Debounce timings, toast durations, and auto-convert delays are scattered as literal values across multiple files.

- [x] **Extract timing constants** — create a shared enum (e.g. `TimingConstants`) with named values for `drawingDebounce` (500ms), `autoConvertDelay` (3s), `hintDuration` (2s), `toastDuration` (1.5s), `errorBannerTimeout` (5s)

### Repeated color definitions

Tag/folder colors are independently defined in `ProjectListView`, `TagEditorView`, and `ProjectDetailView`.

- [x] **Centralize color palette** — extract shared color arrays into a single `Theme` or `AppColors` enum and reference from all views

### Closure-based persistence in AppState

`AppState.onGenerationCreated` uses a closure callback set in `ContentView.onAppear` to bridge to the persistence layer.

- [x] **Replace with `.onChange`** — publish a `@Published var pendingGeneration: GeneratedCode?` and handle persistence in `ContentView` via `.onChange(of:)` instead of a closure

### Test coverage gaps

Only `CodeGenerationResponseTests` and `HTMLTemplateEngineTests` exist. Core logic is untested.

- [x] **Add tests for `GeminiClient`** — mock URLSession to test streaming, error handling, retries
- [x] **Add tests for `AppState`** — test state transitions (idle → converting → result/error), history navigation
- [x] **Add tests for `ProjectStore`** — test CRUD operations with an in-memory SwiftData container
- [x] **Add tests for `StrokeAnalyzer`** — test shape recognition with known stroke patterns
- [x] **Add tests for `RefinementPipeline`** — test prompt construction and response parsing
