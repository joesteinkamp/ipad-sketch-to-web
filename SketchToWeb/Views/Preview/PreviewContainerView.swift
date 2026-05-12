import SwiftUI

/// Container view that lets the user switch between a live web preview
/// and the generated React / HTML source code.
struct PreviewContainerView: View {
    let project: Project
    @EnvironmentObject var appState: AppState

    @State private var selectedTab: PreviewTab = .preview
    @State private var showingShareSheet = false
    @State private var showingSendToDesign = false

    @AppStorage(ShadcnThemeStorage.baseColorKey)
    private var shadcnBaseColor: String = ShadcnThemeStorage.defaultBaseColor.rawValue
    @AppStorage(ShadcnThemeStorage.appearanceKey)
    private var themeAppearance: String = ShadcnThemeStorage.defaultAppearance.rawValue

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
                themeMenu

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

    // MARK: - Theme Menu

    // Two iPadOS quirks we have to work around in this toolbar menu:
    //
    // 1. Picker-in-Menu doesn't write back reliably — selecting an option
    //    dismisses the menu but the binding often never updates, so AppStorage
    //    stays put and the preview stays stale.
    // 2. Button-in-Menu with a dynamic label (Label-when-selected, Text-when-not)
    //    causes SwiftUI to rebuild the underlying UIMenu after a tap. By then
    //    the menu has already dismissed, which is the
    //    `updateVisibleMenuWithBlock while no context menu is visible` console
    //    warning. It's cosmetic, but it's also a signal the menu is fighting
    //    SwiftUI's state model.
    //
    // Toggle-in-Menu sidesteps both: UIMenu renders the checked state as a
    // native checkmark (so the label is static — no rebuild after tap), and
    // the binding writes through every time. The setter coerces "tapping the
    // active option" into a no-op so the user can't accidentally clear the
    // selection.
    @ViewBuilder
    private var themeMenu: some View {
        Menu {
            Section("Base color") {
                ForEach(ShadcnBaseColor.allCases) { color in
                    Toggle(color.displayName, isOn: Binding(
                        get: { shadcnBaseColor == color.rawValue },
                        set: { isOn in if isOn { shadcnBaseColor = color.rawValue } }
                    ))
                }
            }
            Section("Mode") {
                ForEach(ThemeAppearance.allCases) { appearance in
                    Toggle(appearance.displayName, isOn: Binding(
                        get: { themeAppearance == appearance.rawValue },
                        set: { isOn in if isOn { themeAppearance = appearance.rawValue } }
                    ))
                }
            }
        } label: {
            Label("Theme", systemImage: "paintpalette")
        }
        .accessibilityLabel("Theme")
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
