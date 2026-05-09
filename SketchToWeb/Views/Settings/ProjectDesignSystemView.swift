import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Per-project override editor for the design system. When the user enables
/// the override, the project ignores the global `DesignSystem` and uses these
/// fields when generating code.
///
/// Mirrors `DesignSystemSetupView` but reads/writes into the project's
/// `custom*` fields. The shared `DesignPresetGalleryView` is reused for the
/// preset picker.
struct ProjectDesignSystemView: View {

    @Environment(\.dismiss) private var dismiss
    @Bindable var project: Project

    @State private var importError: String?
    @State private var showMarkdownPicker = false
    @State private var showPresetGallery = false

    var body: some View {
        NavigationStack {
            Form {
                toggleSection

                if project.usesCustomDesignSystem {
                    blurbSection
                    presetSection
                    markdownSection
                    notesSection
                }
            }
            .navigationTitle("Project Design")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Import failed",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var toggleSection: some View {
        Section {
            Toggle("Use a different design system for this project", isOn: $project.usesCustomDesignSystem)
        } footer: {
            if project.usesCustomDesignSystem {
                Text("This project will ignore the global design system and use the values below.")
            } else {
                Text("This project inherits the global design system from Settings.")
            }
        }
    }

    @ViewBuilder
    private var blurbSection: some View {
        Section {
            TextField(
                "e.g. Internal admin tool — no logo, monochrome chrome.",
                text: $project.customCompanyBlurb,
                axis: .vertical
            )
            .lineLimit(2...4)
        } header: {
            Text("Project blurb")
        }
    }

    @ViewBuilder
    private var presetSection: some View {
        Section {
            HStack {
                Label("Preset", systemImage: "sparkles")
                Spacer()
                Button(project.customPresetSlug == nil ? "Browse…" : "Change") {
                    showPresetGallery = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if let name = project.customPresetName {
                attachedRow(name: name) {
                    project.customPresetSlug = nil
                    project.customPresetName = nil
                    project.customPresetContent = nil
                }
            }
        } header: {
            Text("Curated preset")
        } footer: {
            Text("Pick a DESIGN.md from the getdesign.md collection.")
        }
        .sheet(isPresented: $showPresetGallery) {
            DesignPresetGalleryView(
                activeSlug: project.customPresetSlug,
                onSelect: { preset, body in
                    project.customPresetSlug = preset.slug
                    project.customPresetName = preset.name
                    project.customPresetContent = body
                },
                onClear: {
                    project.customPresetSlug = nil
                    project.customPresetName = nil
                    project.customPresetContent = nil
                }
            )
        }
    }

    @ViewBuilder
    private var markdownSection: some View {
        Section {
            HStack {
                Label("Upload DESIGN.md", systemImage: "doc.text")
                Spacer()
                Button(project.customMarkdownContent == nil ? "Choose…" : "Replace") {
                    showMarkdownPicker = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if let name = project.customMarkdownFilename {
                attachedRow(name: name) {
                    project.customMarkdownContent = nil
                    project.customMarkdownFilename = nil
                }
            }
        } header: {
            Text("Custom DESIGN.md")
        }
        .fileImporter(
            isPresented: $showMarkdownPicker,
            allowedContentTypes: markdownContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleMarkdownPick(result)
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        Section {
            TextField(
                "e.g. Skip rounded corners on this surface; use sharp edges.",
                text: $project.customNotes,
                axis: .vertical
            )
            .lineLimit(3...8)
        } header: {
            Text("Project-specific notes")
        }
    }

    // MARK: - Helpers

    private var markdownContentTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let mdown = UTType("net.daringfireball.markdown") { types.append(mdown) }
        return types
    }

    private func handleMarkdownPick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else {
                    importError = "Couldn't decode the file as UTF-8 text."
                    return
                }
                project.customMarkdownContent = text
                project.customMarkdownFilename = url.lastPathComponent
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func attachedRow(name: String, onRemove: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
