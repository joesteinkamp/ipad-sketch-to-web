import SwiftUI
import SwiftData

/// A detail view showing metadata and actions for a single project.
struct ProjectDetailView: View {

    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingTagEditor = false

    var onOpen: (() -> Void)?
    var onDelete: (() -> Void)?

    private func tagColor(for tag: String) -> Color {
        AppColors.color(for: tag)
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Project Name", text: $project.name)
                    .font(.headline)

                LabeledContent("Created") {
                    Text(project.createdAt, format: .dateTime.month(.wide).day().year().hour().minute())
                }
            }

            Section("Tags") {
                if project.tags.isEmpty {
                    Button {
                        showingTagEditor = true
                    } label: {
                        Label("Add Tags", systemImage: "tag")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(project.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(tagColor(for: tag).opacity(0.15))
                                .foregroundStyle(tagColor(for: tag))
                                .clipShape(Capsule())
                        }
                    }
                    .onTapGesture {
                        showingTagEditor = true
                    }

                    Button {
                        showingTagEditor = true
                    } label: {
                        Label("Edit Tags", systemImage: "pencil")
                    }
                }
            }
            .popover(isPresented: $showingTagEditor) {
                TagEditorView(project: project)
            }

            Section("Preview") {
                thumbnailSection
            }

            Section("Actions") {
                Button {
                    onOpen?()
                } label: {
                    Label("Open Project", systemImage: "arrow.right.circle")
                }

                Button {
                    duplicateProject()
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }

                Button(role: .destructive) {
                    deleteProject()
                } label: {
                    Label("Delete Project", systemImage: "trash")
                }
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailSection: some View {
        if let data = project.thumbnailData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            ContentUnavailableView(
                "No Drawing Yet",
                systemImage: "scribble",
                description: Text("Open the project and start sketching.")
            )
            .frame(height: 180)
        }
    }

    // MARK: - Actions

    private func duplicateProject() {
        let copy = Project(
            name: "\(project.name) Copy",
            drawingData: project.drawingData,
            generatedHTML: project.generatedHTML,
            generatedReactCode: project.generatedReactCode,
            thumbnailData: project.thumbnailData
        )
        modelContext.insert(copy)
    }

    private func deleteProject() {
        onDelete?()
        modelContext.delete(project)
        dismiss()
    }
}
