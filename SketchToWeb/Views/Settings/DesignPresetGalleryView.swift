import SwiftUI

/// A picker sheet listing curated DESIGN.md presets from the
/// [getdesign.md](https://getdesign.md/) collection. The caller supplies a
/// closure that's invoked with the user's selection (or `nil` to clear), and
/// the view fetches the DESIGN.md body via `DesignSystemImporter.fetchPreset`.
///
/// The same view powers both the global setup sheet and the per-project
/// override editor — the caller just decides where to write the result.
struct DesignPresetGalleryView: View {

    /// Slug of the currently active preset, used to render a "Selected" badge.
    let activeSlug: String?

    /// Called when the user picks a preset and the body fetch succeeds. Pass
    /// the resolved name + body back so the caller can persist them alongside
    /// the slug.
    var onSelect: (DesignPreset, String) -> Void

    /// Called when the user taps "Clear preset". Optional so callers that
    /// don't need a clear affordance (e.g. a first-time picker) can omit it.
    var onClear: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var presets: [DesignPreset] = DesignPreset.loadCatalog()
    @State private var search: String = ""
    @State private var loadingSlug: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let active = activePreset {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Currently using")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(active.name)
                                    .font(.headline)
                            }
                            Spacer()
                            if onClear != nil {
                                Button(role: .destructive) {
                                    onClear?()
                                    dismiss()
                                } label: {
                                    Text("Clear")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                ForEach(groupedPresets, id: \.0) { category, items in
                    Section(category) {
                        ForEach(items) { preset in
                            presetRow(preset)
                        }
                    }
                }

                if filteredPresets.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No presets",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different search.")
                        )
                    }
                }
            }
            .searchable(text: $search, prompt: "Search presets")
            .navigationTitle("Design Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                "Couldn't load preset",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func presetRow(_ preset: DesignPreset) -> some View {
        Button {
            select(preset)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(preset.name)
                            .font(.body.weight(.semibold))
                        if preset.slug == activeSlug {
                            Text("Selected")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    Text(preset.blurb)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if loadingSlug == preset.slug {
                    ProgressView().controlSize(.small)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loadingSlug != nil)
    }

    // MARK: - Data

    private var activePreset: DesignPreset? {
        guard let slug = activeSlug else { return nil }
        return presets.first { $0.slug == slug }
    }

    private var filteredPresets: [DesignPreset] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return presets }
        return presets.filter {
            $0.name.lowercased().contains(trimmed) ||
            $0.slug.lowercased().contains(trimmed) ||
            $0.blurb.lowercased().contains(trimmed) ||
            $0.category.lowercased().contains(trimmed)
        }
    }

    private var groupedPresets: [(String, [DesignPreset])] {
        let groups = Dictionary(grouping: filteredPresets, by: \.category)
        return groups
            .map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.0 < $1.0 }
    }

    private func select(_ preset: DesignPreset) {
        loadingSlug = preset.slug
        Task {
            defer { loadingSlug = nil }
            do {
                let body = try await DesignSystemImporter.fetchPreset(slug: preset.slug)
                onSelect(preset, body)
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
