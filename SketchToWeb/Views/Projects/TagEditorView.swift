import SwiftUI
import SwiftData

/// A popover view for editing tags on a project.
/// Shows existing tags as removable chips and provides autocomplete for adding new ones.
struct TagEditorView: View {

    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Project.createdAt, order: .reverse)
    private var allProjects: [Project]

    @State private var newTagText: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tags")
                .font(.headline)

            // Existing tags as removable chips
            if !project.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(project.tags, id: \.self) { tag in
                        tagChip(tag)
                    }
                }
            } else {
                Text("No tags yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Add new tag
            HStack {
                TextField("Add a tag...", text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        addTag()
                    }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    addTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Autocomplete suggestions
            let suggestions = suggestedTags
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggestions")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 6) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                addTag(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.quaternary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 280, idealWidth: 320)
        .onAppear {
            isTextFieldFocused = true
        }
    }

    // MARK: - Tag Chip

    @ViewBuilder
    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
                .fontWeight(.medium)

            Button {
                removeTag(tag)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tagColor(for: tag).opacity(0.15))
        .foregroundStyle(tagColor(for: tag))
        .clipShape(Capsule())
    }

    // MARK: - Suggestions

    /// Returns tags used across all projects that match the current input and aren't already on this project.
    private var suggestedTags: [String] {
        let existingTags = Set(project.tags)
        let allTags = Set(allProjects.flatMap(\.tags))
        let available = allTags.subtracting(existingTags)

        if newTagText.trimmingCharacters(in: .whitespaces).isEmpty {
            return Array(available).sorted().prefix(10).map { $0 }
        }

        let query = newTagText.lowercased()
        return available
            .filter { $0.lowercased().contains(query) }
            .sorted()
            .prefix(10)
            .map { $0 }
    }

    // MARK: - Actions

    private func addTag(_ tag: String? = nil) {
        let tagToAdd = (tag ?? newTagText).trimmingCharacters(in: .whitespaces).lowercased()
        guard !tagToAdd.isEmpty, !project.tags.contains(tagToAdd) else { return }
        project.tags.append(tagToAdd)
        newTagText = ""
    }

    private func removeTag(_ tag: String) {
        project.tags.removeAll { $0 == tag }
    }

    /// Deterministic color based on tag string hash.
    private func tagColor(for tag: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .indigo, .red, .mint, .cyan]
        let index = abs(tag.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - Flow Layout

/// A simple horizontal wrapping layout for tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }

        return (CGSize(width: maxX, height: currentY + rowHeight), positions)
    }
}
