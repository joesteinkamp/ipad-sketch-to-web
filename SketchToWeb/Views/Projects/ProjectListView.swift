import SwiftUI
import SwiftData

/// The sidebar list of all projects, organized by folders with search and tag filtering.
struct ProjectListView: View {

    @Query(sort: \Project.createdAt, order: .reverse)
    private var projects: [Project]

    @Query(sort: \ProjectFolder.createdAt, order: .reverse)
    private var folders: [ProjectFolder]

    @Environment(\.modelContext) private var modelContext
    @Binding var selectedProject: Project?

    @State private var searchText: String = ""
    @State private var showNewFolderDialog = false
    @State private var newFolderName: String = ""
    @State private var renamingFolder: ProjectFolder?
    @State private var renameFolderText: String = ""
    @State private var colorPickerFolder: ProjectFolder?

    // Predefined folder colors
    private let folderColors: [(name: String, hex: String)] = [
        ("Blue", "#007AFF"),
        ("Purple", "#AF52DE"),
        ("Green", "#34C759"),
        ("Orange", "#FF9500"),
        ("Red", "#FF3B30"),
        ("Teal", "#5AC8FA"),
        ("Pink", "#FF2D55"),
        ("Indigo", "#5856D6"),
    ]

    var body: some View {
        List(selection: $selectedProject) {
            // All Projects section (flat, filtered)
            Section("All Projects") {
                ForEach(filteredProjects) { project in
                    NavigationLink(value: project) {
                        projectRow(project)
                    }
                    .draggable(project.id.uuidString)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteProject(project)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            // Per-folder sections
            ForEach(folders) { folder in
                Section {
                    let folderProjects = filteredProjects(in: folder)
                    if folderProjects.isEmpty {
                        Text("No projects")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(folderProjects) { project in
                            NavigationLink(value: project) {
                                projectRow(project)
                            }
                            .draggable(project.id.uuidString)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteProject(project)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    project.folder = nil
                                } label: {
                                    Label("Unfiled", systemImage: "tray.and.arrow.up")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                } header: {
                    folderHeader(folder)
                }
                .dropDestination(for: String.self) { droppedItems, _ in
                    handleDrop(droppedItems, into: folder)
                    return true
                }
            }

            // Unfiled section
            Section {
                let unfiled = unfiledProjects
                if unfiled.isEmpty {
                    Text("No unfiled projects")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(unfiled) { project in
                        NavigationLink(value: project) {
                            projectRow(project)
                        }
                        .draggable(project.id.uuidString)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteProject(project)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Label("Unfiled", systemImage: "tray")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Filter by name or tag")
        .overlay {
            if projects.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "doc.on.doc",
                    description: Text("Tap \"New Project\" to get started.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    createProject()
                } label: {
                    Label("New Project", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    newFolderName = ""
                    showNewFolderDialog = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .navigationTitle("Projects")
        .alert("New Folder", isPresented: $showNewFolderDialog) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                createFolder()
            }
            .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Enter a name for the new folder.")
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("Folder name", text: $renameFolderText)
            Button("Cancel", role: .cancel) {
                renamingFolder = nil
            }
            Button("Rename") {
                renamingFolder?.name = renameFolderText
                renamingFolder = nil
            }
        } message: {
            Text("Enter a new name for the folder.")
        }
        .sheet(item: $colorPickerFolder) { folder in
            folderColorPicker(folder)
        }
    }

    // MARK: - Filtered Data

    private var filteredProjects: [Project] {
        guard !searchText.isEmpty else { return projects }
        let query = searchText.lowercased()
        return projects.filter { project in
            project.name.lowercased().contains(query) ||
            project.tags.contains { $0.lowercased().contains(query) }
        }
    }

    private func filteredProjects(in folder: ProjectFolder) -> [Project] {
        filteredProjects.filter { $0.folder?.id == folder.id }
    }

    private var unfiledProjects: [Project] {
        filteredProjects.filter { $0.folder == nil }
    }

    // MARK: - Folder Header

    @ViewBuilder
    private func folderHeader(_ folder: ProjectFolder) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(folder.color)
                .frame(width: 10, height: 10)

            Text(folder.name)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .contextMenu {
            Button {
                renameFolderText = folder.name
                renamingFolder = folder
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                colorPickerFolder = folder
            } label: {
                Label("Change Color", systemImage: "paintpalette")
            }

            Divider()

            Button(role: .destructive) {
                deleteFolder(folder)
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }

    // MARK: - Folder Color Picker

    @ViewBuilder
    private func folderColorPicker(_ folder: ProjectFolder) -> some View {
        NavigationStack {
            List {
                ForEach(folderColors, id: \.hex) { colorOption in
                    Button {
                        folder.colorHex = colorOption.hex
                        colorPickerFolder = nil
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: colorOption.hex) ?? .blue)
                                .frame(width: 24, height: 24)

                            Text(colorOption.name)

                            Spacer()

                            if folder.colorHex == colorOption.hex {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Folder Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        colorPickerFolder = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Row

    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 12) {
            thumbnailView(for: project)
                .frame(width: 56, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(project.createdAt, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !project.tags.isEmpty {
                        Text("--")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)

                        ForEach(project.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.quaternary)
                                .clipShape(Capsule())
                        }

                        if project.tags.count > 3 {
                            Text("+\(project.tags.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func thumbnailView(for project: Project) -> some View {
        if let data = project.thumbnailData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.tertiarySystemFill))
                .overlay {
                    Image(systemName: "pencil.tip.crop.circle")
                        .foregroundStyle(.secondary)
                }
        }
    }

    // MARK: - Drag and Drop

    private func handleDrop(_ items: [String], into folder: ProjectFolder) {
        for uuidString in items {
            guard let uuid = UUID(uuidString: uuidString),
                  let project = projects.first(where: { $0.id == uuid }) else { continue }
            project.folder = folder
        }
    }

    // MARK: - Actions

    private func createProject() {
        let project = Project(name: "Untitled Sketch")
        modelContext.insert(project)
        selectedProject = project
    }

    private func deleteProject(_ project: Project) {
        if selectedProject?.id == project.id {
            selectedProject = nil
        }
        modelContext.delete(project)
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let folder = ProjectFolder(name: trimmed)
        modelContext.insert(folder)
    }

    private func deleteFolder(_ folder: ProjectFolder) {
        // Move all projects to unfiled before deleting the folder
        for project in folder.projects {
            project.folder = nil
        }
        modelContext.delete(folder)
    }
}

