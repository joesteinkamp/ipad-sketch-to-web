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

    @Query private var allGenerations: [Generation]

    /// The id of the generation currently loaded in the preview.
    @State private var activeGenerationID: UUID?

    // Filter generations to the current project AND the active design-system
    // key so the timeline doesn't mix shadcn / Material / Carbon results
    // together. The preview's toggle owns the key; this view just reflects it.
    private var generations: [Generation] {
        let key = appState.activeDesignSystemKey
        return allGenerations
            .filter { $0.project?.id == project.id && $0.designSystemKey == key }
            .sorted { $0.createdAt > $1.createdAt }
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

    var body: some View {
        HStack(spacing: 12) {
            // Drawing thumbnail
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

                Text(String(generation.htmlPreview.prefix(100)))
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
    }

    @ViewBuilder
    private var drawingThumbnail: some View {
        if let drawing = try? PKDrawing(data: generation.decompressedSnapshot) {
            let image = drawing.image(
                from: drawing.bounds,
                scale: UIScreen.main.scale
            )
            Image(uiImage: image)
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
}
