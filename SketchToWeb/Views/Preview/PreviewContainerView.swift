import SwiftUI

/// Container view that lets the user switch between a live web preview
/// and the generated React / HTML source code.
struct PreviewContainerView: View {
    let project: Project
    @EnvironmentObject var appState: AppState

    @State private var selectedTab: PreviewTab = .preview
    @State private var showingShareSheet = false
    @State private var showingSendToDesign = false

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

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingSendToDesign = true
                } label: {
                    Label("Send to Figma", systemImage: "rectangle.connected.to.line.below")
                }
                .disabled(appState.generatedResult == nil)

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
        .sheet(isPresented: $showingSendToDesign) {
            SendToDesignSheet()
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
