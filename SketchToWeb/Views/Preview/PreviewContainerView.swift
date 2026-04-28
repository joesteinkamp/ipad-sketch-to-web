import SwiftUI
import SwiftData

/// Container view that lets the user switch between a live web preview
/// and the generated React / HTML source code.
struct PreviewContainerView: View {
    let project: Project
    @EnvironmentObject var appState: AppState

    @Query(sort: \Generation.createdAt, order: .reverse) private var allGenerations: [Generation]

    @State private var selectedTab: PreviewTab = .preview
    @State private var showingShareSheet = false

    @AppStorage("compareDesignSystemsEnabled") private var compareDesignSystemsEnabled: Bool = false
    @AppStorage("activePublicDesignSystemID") private var activePublicDesignSystemID: String = "material-3"

    /// Generations belonging to the current project. Drives the cache lookup
    /// in `setActiveDesignSystem`.
    private var projectGenerations: [Generation] {
        allGenerations.filter { $0.project?.id == project.id }
    }

    /// The currently-active public DS resolved from the catalog. Falls back
    /// to the first non-default catalog entry if the stored id is unknown,
    /// so the toggle always has something to show.
    private var activePublicDesignSystem: PublicDesignSystem? {
        let catalog = appState.publicDesignSystemCatalog
        guard !catalog.isEmpty else { return nil }
        return catalog.first { $0.id == activePublicDesignSystemID && !$0.isDefault }
            ?? catalog.first { !$0.isDefault }
    }

    // MARK: - Tab Enum

    private enum PreviewTab: String, CaseIterable, Identifiable {
        case preview = "Preview"
        case react = "React"
        case html = "HTML"

        var id: String { rawValue }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if compareDesignSystemsEnabled, let publicDS = activePublicDesignSystem {
                designSystemToggle(publicDS: publicDS)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            // Segmented tab picker
            Picker("Preview Mode", selection: $selectedTab) {
                ForEach(PreviewTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Tab content
            if let result = appState.generatedResult {
                tabContent(for: result)
            } else {
                placeholderView
            }
        }
        .background(Color(.secondarySystemBackground))
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    appState.goBack()
                } label: {
                    Label("Previous Version", systemImage: "chevron.left")
                }
                .disabled(!appState.canGoBack)

                Button {
                    appState.goForward()
                } label: {
                    Label("Next Version", systemImage: "chevron.right")
                }
                .disabled(!appState.canGoForward)

                if appState.generationHistory.count > 1 {
                    Text("v\(appState.generationHistoryIndex + 1)/\(appState.generationHistory.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(appState.generatedResult == nil)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let content = shareContent {
                ActivityViewController(activityItems: [content])
            }
        }
    }

    // MARK: - Design System Toggle

    @ViewBuilder
    private func designSystemToggle(publicDS: PublicDesignSystem) -> some View {
        let isUserActive = appState.activeDesignSystemKey == PublicDesignSystem.userDesignSystemKey
        let nonDefaultCatalog = appState.publicDesignSystemCatalog.filter { !$0.isDefault }

        HStack(spacing: 8) {
            // Two-state segmented control: Yours | <public DS>.
            Picker(
                "Design System",
                selection: Binding(
                    get: { isUserActive ? PublicDesignSystem.userDesignSystemKey : publicDS.id },
                    set: { newKey in
                        appState.setActiveDesignSystem(newKey, cachedGenerations: projectGenerations)
                    }
                )
            ) {
                Text("Yours").tag(PublicDesignSystem.userDesignSystemKey)
                Text(publicDS.displayShortName).tag(publicDS.id)
            }
            .pickerStyle(.segmented)

            // Menu chevron to switch which public DS is the comparison target.
            if nonDefaultCatalog.count > 1 {
                Menu {
                    ForEach(nonDefaultCatalog) { entry in
                        Button {
                            activePublicDesignSystemID = entry.id
                            // If we were currently viewing the public side,
                            // pivot to the new one immediately.
                            if !isUserActive {
                                appState.setActiveDesignSystem(entry.id, cachedGenerations: projectGenerations)
                            }
                        } label: {
                            HStack {
                                Text(entry.name)
                                if entry.id == publicDS.id {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                        .accessibilityLabel("Choose comparison design system")
                }
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(for result: GeneratedCode) -> some View {
        switch selectedTab {
        case .preview:
            AnnotatablePreviewView(htmlContent: result.htmlPreview)
        case .react:
            CodePreviewView(code: result.reactCode, language: "jsx")
        case .html:
            CodePreviewView(code: result.htmlPreview, language: "html")
        }
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        ContentUnavailableView {
            Label("No Preview", systemImage: "wand.and.stars")
        } description: {
            Text("Draw a UI sketch and tap Convert to see the result here")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Share Content

    private var shareContent: String? {
        guard let result = appState.generatedResult else { return nil }
        switch selectedTab {
        case .preview:
            return result.htmlPreview
        case .react:
            return result.reactCode
        case .html:
            return result.htmlPreview
        }
    }
}

// MARK: - UIActivityViewController Wrapper

/// Minimal UIKit wrapper for presenting a share sheet from SwiftUI.
private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No dynamic updates needed.
    }
}
