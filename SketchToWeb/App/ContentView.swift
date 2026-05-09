import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \DesignSystem.createdAt) private var designSystems: [DesignSystem]
    @State private var selectedProject: Project?
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            ProjectListView(selectedProject: $selectedProject)
        } detail: {
            if let project = selectedProject {
                HStack(spacing: 0) {
                    CanvasView(project: $selectedProject)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    PreviewContainerView(project: project)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .navigationTitle(project.name)
                .toolbar {
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
            updateDesignSystemSnapshot()
        }
        .onChange(of: appState.pendingGeneration) { _, generation in
            guard let generation else { return }
            modelContext.insert(generation)
        }
        .onChange(of: designSystems.first?.updatedAt) { _, _ in
            updateDesignSystemSnapshot()
        }
        .onChange(of: selectedProject?.usesCustomDesignSystem) { _, _ in
            updateDesignSystemSnapshot()
        }
        .onChange(of: selectedProject?.customPresetSlug) { _, _ in
            updateDesignSystemSnapshot()
        }
        .onChange(of: selectedProject?.customMarkdownContent) { _, _ in
            updateDesignSystemSnapshot()
        }
        .onChange(of: selectedProject?.customNotes) { _, _ in
            updateDesignSystemSnapshot()
        }
        .onChange(of: selectedProject?.customCompanyBlurb) { _, _ in
            updateDesignSystemSnapshot()
        }
        .onChange(of: showingSettings) { _, isShowing in
            // Settings sheet is the only surface that edits design-system fields,
            // so re-snapshot when it closes to pick up any edits in one shot.
            if !isShowing { updateDesignSystemSnapshot() }
        }
        .onAppear {
            appState.currentProject = selectedProject
            updateDesignSystemSnapshot()
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
    private func updateDesignSystemSnapshot() {
        if let project = selectedProject, project.usesCustomDesignSystem {
            let snapshot = makeProjectSnapshot(project)
            appState.designSystemSnapshot = snapshot.isEmpty ? nil : snapshot
            return
        }
        let snapshot = designSystems.first?.snapshot()
        appState.designSystemSnapshot = (snapshot?.isEmpty ?? true) ? nil : snapshot
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
            fontFileNames: [],
            assetFileNames: []
        )
    }
}

// CanvasView is now defined in Views/Canvas/CanvasView.swift

// PreviewContainerView moved to Views/Preview/PreviewContainerView.swift
