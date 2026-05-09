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
        }
        .onChange(of: appState.pendingGeneration) { _, generation in
            guard let generation else { return }
            modelContext.insert(generation)
        }
        .onChange(of: designSystems.first?.updatedAt) { _, _ in
            updateDesignSystemSnapshot()
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
    private func updateDesignSystemSnapshot() {
        let snapshot = designSystems.first?.snapshot()
        appState.designSystemSnapshot = (snapshot?.isEmpty ?? true) ? nil : snapshot
    }
}

// CanvasView is now defined in Views/Canvas/CanvasView.swift

// PreviewContainerView moved to Views/Preview/PreviewContainerView.swift
