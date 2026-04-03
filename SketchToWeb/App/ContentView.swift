import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
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
        }
        .onAppear {
            appState.currentProject = selectedProject
            appState.onGenerationCreated = { generation in
                modelContext.insert(generation)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private func createNewProject() {
        let project = Project(name: "Untitled Sketch")
        modelContext.insert(project)
        selectedProject = project
    }
}

// CanvasView is now defined in Views/Canvas/CanvasView.swift

// PreviewContainerView moved to Views/Preview/PreviewContainerView.swift
