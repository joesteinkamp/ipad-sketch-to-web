import SwiftUI
import SwiftData

enum LayoutMode: String, CaseIterable, Identifiable {
    case sketch, split, preview
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .sketch:  return "pencil.tip"
        case .split:   return "rectangle.split.2x1"
        case .preview: return "rectangle"
        }
    }

    var label: String {
        switch self {
        case .sketch:  return "Sketch"
        case .split:   return "Split"
        case .preview: return "Preview"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \DesignSystem.createdAt) private var designSystems: [DesignSystem]
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var selectedProject: Project?
    @State private var showingSettings = false
    @AppStorage("layoutMode") private var layoutModeRaw: String = LayoutMode.split.rawValue

    private var layoutMode: LayoutMode {
        LayoutMode(rawValue: layoutModeRaw) ?? .split
    }

    var body: some View {
        NavigationSplitView {
            ProjectListView(selectedProject: $selectedProject)
        } detail: {
            if let project = selectedProject {
                Group {
                    switch layoutMode {
                    case .sketch:
                        CanvasView(project: $selectedProject)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .split:
                        HStack(spacing: 0) {
                            CanvasView(project: $selectedProject)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                            Divider()

                            PreviewContainerView(project: project)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    case .preview:
                        PreviewContainerView(project: project)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: layoutMode)
                .navigationTitle(project.name)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("Layout", selection: Binding(
                            get: { layoutMode },
                            set: { layoutModeRaw = $0.rawValue }
                        )) {
                            ForEach(LayoutMode.allCases) { mode in
                                Image(systemName: mode.symbol)
                                    .accessibilityLabel(mode.label)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "pencil.and.outline",
                    description: Text("Select or create a project to start sketching.")
                )
            }
        }
        .onChange(of: selectedProject) { _, newProject in
            appState.currentProject = newProject
            updateDesignSystemSnapshot(regenerateOnChange: false)
        }
        .onChange(of: appState.pendingGeneration) { _, generation in
            guard let generation else { return }
            modelContext.insert(generation)
        }
        .onChange(of: designSystems.first?.updatedAt) { _, _ in
            updateDesignSystemSnapshot(regenerateOnChange: true)
        }
        .onChange(of: selectedProject?.usesCustomDesignSystem) { _, _ in
            updateDesignSystemSnapshot(regenerateOnChange: true)
        }
        .onChange(of: selectedProject?.customPresetSlug) { _, _ in
            updateDesignSystemSnapshot(regenerateOnChange: true)
        }
        .onChange(of: selectedProject?.customMarkdownContent) { _, _ in
            updateDesignSystemSnapshot(regenerateOnChange: true)
        }
        .onChange(of: selectedProject?.customNotes) { _, _ in
            updateDesignSystemSnapshot(regenerateOnChange: true)
        }
        .onChange(of: selectedProject?.customCompanyBlurb) { _, _ in
            updateDesignSystemSnapshot(regenerateOnChange: true)
        }
        .onChange(of: selectedProject?.customIconLibraryRaw) { _, _ in
            updateDesignSystemSnapshot(regenerateOnChange: true)
        }
        .onChange(of: showingSettings) { _, isShowing in
            // Settings sheet is the only surface that edits design-system fields,
            // so re-snapshot when it closes to pick up any edits in one shot.
            if !isShowing { updateDesignSystemSnapshot(regenerateOnChange: true) }
        }
        .onAppear {
            if selectedProject == nil {
                selectedProject = projects.first
            }
            appState.currentProject = selectedProject
            updateDesignSystemSnapshot(regenerateOnChange: false)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .errorBanner(appState.conversionError) {
            appState.conversionError = nil
        }
    }

    private func createNewProject() {
        let project = Project(name: "Untitled Sketch")
        modelContext.insert(project)
        selectedProject = project
    }

    /// Pushes a snapshot of the current design system into `AppState` so the
    /// pipelines can read it without touching SwiftData off the main actor.
    ///
    /// Resolution order: if the active project has `usesCustomDesignSystem` on,
    /// build a snapshot from the project's `custom*` fields and ignore the
    /// global record entirely. Otherwise fall back to the global design system.
    ///
    /// When `regenerateOnChange` is true and the snapshot actually changes and a
    /// preview already exists, kick off a new conversion so the visible preview
    /// reflects the new design system (e.g. after picking a preset DESIGN.md).
    private func updateDesignSystemSnapshot(regenerateOnChange: Bool) {
        let newSnapshot: DesignSystemSnapshot?
        if let project = selectedProject, project.usesCustomDesignSystem {
            let snapshot = makeProjectSnapshot(project)
            newSnapshot = snapshot.hasAnyContent ? snapshot : nil
        } else {
            let snapshot = designSystems.first?.snapshot()
            newSnapshot = (snapshot?.hasAnyContent ?? false) ? snapshot : nil
        }

        let didChange = appState.designSystemSnapshot != newSnapshot
        appState.designSystemSnapshot = newSnapshot

        guard regenerateOnChange, didChange else { return }
        guard appState.generatedResult != nil else { return }
        guard !appState.isConverting, !appState.isRefining else { return }
        appState.convertDrawing()
    }

    /// Builds a `DesignSystemSnapshot` from a project's per-project override
    /// fields. Mirrors `DesignSystem.snapshot()` for the subset of fields the
    /// per-project surface exposes.
    private func makeProjectSnapshot(_ project: Project) -> DesignSystemSnapshot {
        DesignSystemSnapshot(
            companyBlurb: project.customCompanyBlurb,
            notes: project.customNotes,
            markdownContent: project.customMarkdownContent,
            markdownFilename: project.customMarkdownFilename,
            sourceURL: nil,
            sourceURLContent: nil,
            zipExtractedContent: nil,
            zipFilename: nil,
            presetSlug: project.customPresetSlug,
            presetName: project.customPresetName,
            presetContent: project.customPresetContent,
            iconLibrary: project.customIconLibrary,
            fontFileNames: [],
            assetFileNames: []
        )
    }
}

// CanvasView is now defined in Views/Canvas/CanvasView.swift

// PreviewContainerView moved to Views/Preview/PreviewContainerView.swift
