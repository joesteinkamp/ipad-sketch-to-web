import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Setup sheet for the user's design system. Lets the user provide a company
/// blurb, attach a `DESIGN.md`/markdown file, link a code URL (GitHub, GitLab,
/// Bitbucket, or any raw URL), upload a zip archive, attach fonts/assets, and
/// add free-form notes. Mirrors the layout from the product spec.
///
/// The outer view fetches-or-creates the singleton `DesignSystem` and hands it
/// to the inner editor, so the editor can use a non-optional `@Bindable`.
struct DesignSystemSetupView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DesignSystem.createdAt) private var designSystems: [DesignSystem]

    var body: some View {
        if let existing = designSystems.first {
            DesignSystemEditorView(designSystem: existing)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    modelContext.insert(DesignSystem())
                }
        }
    }
}

private struct DesignSystemEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @Bindable var designSystem: DesignSystem

    @State private var sourceURLInput: String = ""
    @State private var importTask: ImportKind?
    @State private var importError: String?

    @State private var showMarkdownPicker = false
    @State private var showZipPicker = false
    @State private var showFontPicker = false
    @State private var showAssetPicker = false

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                blurbSection
                resourcesSection
                notesSection
            }
            .navigationTitle("Design System")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        designSystem.updatedAt = Date()
                        dismiss()
                    }
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
    private var headerSection: some View {
        Section {
            VStack(alignment: .center, spacing: 8) {
                Image(systemName: "square.on.square.dashed")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Set up your design system")
                    .font(.title2.weight(.semibold))
                Text("Tell us about your company and attach any design resources you have.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var blurbSection: some View {
        Section {
            TextField(
                "e.g. Mission Impastabowl: fast-casual pasta restaurant…",
                text: $designSystem.companyBlurb,
                axis: .vertical
            )
            .lineLimit(2...5)
        } header: {
            Text("Company name and blurb")
        } footer: {
            Text("Or the name of your design system.")
        }
    }

    @ViewBuilder
    private var resourcesSection: some View {
        Section {
            markdownRow
            githubURLRow
            zipRow
            fontsRow
            assetsRow
        } header: {
            Text("Examples of your design system (all optional)")
        } footer: {
            Text("What works best: code and designs for your design system and your code products.")
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        Section {
            TextField(
                "e.g. We use a warm, earthy color palette with rounded corners…",
                text: $designSystem.notes,
                axis: .vertical
            )
            .lineLimit(3...8)
        } header: {
            Text("Any other notes?")
        }
    }

    // MARK: - Resource Rows

    @ViewBuilder
    private var markdownRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Upload DESIGN.md", systemImage: "doc.text")
                Spacer()
                Button(designSystem.markdownContent == nil ? "Choose…" : "Replace") {
                    showMarkdownPicker = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if let name = designSystem.markdownFilename {
                attachedRow(name: name) {
                    designSystem.markdownContent = nil
                    designSystem.markdownFilename = nil
                    designSystem.updatedAt = Date()
                }
            }
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
    private var githubURLRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Link code on GitHub", systemImage: "link")
                Spacer()
            }
            HStack {
                TextField("https://github.com/owner/repo", text: $sourceURLInput)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if importTask == .url {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Add") {
                        Task { await fetchSourceURL() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(sourceURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if let resolvedURL = designSystem.sourceURL,
               designSystem.sourceURLContent != nil {
                attachedRow(name: resolvedURL) {
                    designSystem.sourceURL = nil
                    designSystem.sourceURLContent = nil
                    designSystem.updatedAt = Date()
                }
            }
            Text("Works with GitHub, GitLab, Bitbucket, or a raw URL.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var zipRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Upload a .zip", systemImage: "archivebox")
                Spacer()
                if importTask == .zip {
                    ProgressView().controlSize(.small)
                } else {
                    Button(designSystem.zipExtractedContent == nil ? "Choose…" : "Replace") {
                        showZipPicker = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if let name = designSystem.zipFilename {
                attachedRow(name: name) {
                    designSystem.zipExtractedContent = nil
                    designSystem.zipFilename = nil
                    designSystem.updatedAt = Date()
                }
            }
            Text("We'll pull DESIGN.md, README, tailwind config, and tokens.json — no full codebase upload.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fileImporter(
            isPresented: $showZipPicker,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            handleZipPick(result)
        }
    }

    @ViewBuilder
    private var fontsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Add fonts", systemImage: "textformat")
                Spacer()
                Button("Choose…") { showFontPicker = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            ForEach(designSystem.fontFilePaths, id: \.self) { path in
                attachedRow(name: (path as NSString).lastPathComponent) {
                    designSystem.fontFilePaths.removeAll { $0 == path }
                    designSystem.updatedAt = Date()
                }
            }
        }
        .fileImporter(
            isPresented: $showFontPicker,
            allowedContentTypes: [.font],
            allowsMultipleSelection: true
        ) { result in
            handlePickerResult(result, subfolder: "Fonts") { paths in
                designSystem.fontFilePaths.append(contentsOf: paths)
            }
        }
    }

    @ViewBuilder
    private var assetsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Add logos and assets", systemImage: "photo")
                Spacer()
                Button("Choose…") { showAssetPicker = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            ForEach(designSystem.assetFilePaths, id: \.self) { path in
                attachedRow(name: (path as NSString).lastPathComponent) {
                    designSystem.assetFilePaths.removeAll { $0 == path }
                    designSystem.updatedAt = Date()
                }
            }
        }
        .fileImporter(
            isPresented: $showAssetPicker,
            allowedContentTypes: [.image, .svg],
            allowsMultipleSelection: true
        ) { result in
            handlePickerResult(result, subfolder: "Assets") { paths in
                designSystem.assetFilePaths.append(contentsOf: paths)
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

    // MARK: - Import Handlers

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
                designSystem.markdownContent = text
                designSystem.markdownFilename = url.lastPathComponent
                designSystem.updatedAt = Date()
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func handleZipPick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            importTask = .zip
            Task {
                defer { importTask = nil }
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                do {
                    let extracted = try DesignSystemImporter.extractRelevantText(fromZip: url)
                    designSystem.zipExtractedContent = extracted
                    designSystem.zipFilename = url.lastPathComponent
                    designSystem.updatedAt = Date()
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
    }

    private func handlePickerResult(
        _ result: Result<[URL], Error>,
        subfolder: String,
        apply: ([String]) -> Void
    ) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            var newPaths: [String] = []
            for url in urls {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                do {
                    let path = try DesignSystemImporter.persistImportedFile(at: url, subfolder: subfolder)
                    newPaths.append(path)
                } catch {
                    importError = error.localizedDescription
                }
            }
            if !newPaths.isEmpty {
                apply(newPaths)
                designSystem.updatedAt = Date()
            }
        }
    }

    private func fetchSourceURL() async {
        let raw = sourceURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        importTask = .url
        defer { importTask = nil }

        do {
            let result = try await DesignSystemImporter.fetchFromSourceURL(raw)
            designSystem.sourceURL = result.resolvedURL
            designSystem.sourceURLContent = result.content
            designSystem.updatedAt = Date()
            sourceURLInput = ""
        } catch {
            importError = error.localizedDescription
        }
    }

    // MARK: - Types

    private enum ImportKind: Equatable {
        case url
        case zip
    }
}

private extension UTType {
    static var svg: UTType { UTType("public.svg-image") ?? .image }
}
