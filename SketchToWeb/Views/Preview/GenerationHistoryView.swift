import SwiftUI
import SwiftData
import PencilKit

/// A sheet/sidebar that shows a vertical timeline of all generations for the
/// current project, letting the user tap to load a past generation or swipe to delete.
struct GenerationHistoryView: View {

    let project: Project
    @EnvironmentObject var appState: AppState

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var generations: [Generation]

    /// The id of the generation currently loaded in the preview.
    @State private var activeGenerationID: UUID?

    init(project: Project) {
        self.project = project
        let projectID = project.id
        let predicate = #Predicate<Generation> { generation in
            generation.project?.id == projectID
        }
        _generations = Query(
            filter: predicate,
            sort: [SortDescriptor(\Generation.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if generations.isEmpty {
                    ContentUnavailableView {
                        Label("No Generations", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Convert a sketch to see generation history here.")
                    }
                } else {
                    List {
                        ForEach(generations) { generation in
                            GenerationRow(
                                generation: generation,
                                isActive: generation.id == activeGenerationID
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                loadGeneration(generation)
                            }
                        }
                        .onDelete(perform: deleteGenerations)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadGeneration(_ generation: Generation) {
        activeGenerationID = generation.id
        appState.generatedResult = GeneratedCode(
            htmlPreview: generation.htmlPreview,
            reactCode: generation.reactCode
        )
    }

    private func deleteGenerations(at offsets: IndexSet) {
        let toDelete = offsets.map { generations[$0] }
        for generation in toDelete {
            modelContext.delete(generation)
        }
    }
}

// MARK: - Row

private struct GenerationRow: View {
    let generation: Generation
    let isActive: Bool

    @Environment(\.displayScale) private var displayScale

    @State private var thumbnailImage: UIImage?
    @State private var snippet: String = ""

    var body: some View {
        HStack(spacing: 12) {
            drawingThumbnail
                .frame(width: 60, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(generation.createdAt, style: .relative)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? .primary : .secondary)

                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 4)
        .task(id: generation.id) {
            await loadRowContent()
        }
    }

    @ViewBuilder
    private var drawingThumbnail: some View {
        if let thumbnailImage {
            Image(uiImage: thumbnailImage)
                .resizable()
                .scaledToFit()
                .background(Color(.systemBackground))
        } else {
            Rectangle()
                .fill(Color(.tertiarySystemFill))
                .overlay {
                    Image(systemName: "scribble")
                        .foregroundStyle(.quaternary)
                }
        }
    }

    /// Reads the snapshot blob + html prefix on the main actor (SwiftData models
    /// aren't Sendable), then hands the raw bytes off to a detached task so the
    /// zlib decompress and PKDrawing render don't block the list scroll.
    private func loadRowContent() async {
        let snapshotData = generation.drawingSnapshot
        let previewPrefix = String(generation.htmlPreview.prefix(100))
        let scale = displayScale

        snippet = previewPrefix

        let image: UIImage? = await Task.detached(priority: .userInitiated) {
            let decompressed = (try? (snapshotData as NSData).decompressed(using: .zlib)) as Data? ?? snapshotData
            guard let drawing = try? PKDrawing(data: decompressed) else { return nil }
            let bounds = drawing.bounds
            guard bounds.width > 0, bounds.height > 0 else { return nil }
            return drawing.image(from: bounds, scale: scale)
        }.value

        thumbnailImage = image
    }
}
