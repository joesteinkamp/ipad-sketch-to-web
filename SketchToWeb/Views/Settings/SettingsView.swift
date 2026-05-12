import SwiftUI

/// A settings sheet for configuring the Gemini API connection and model selection.
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""
    @State private var showingDesignSystem = false
    @State private var showingProjectDesign = false

    @AppStorage("selectedModel") private var selectedModel: String = "gemini-3.1-pro-preview"
    @AppStorage("autoConvertEnabled") private var autoConvertEnabled: Bool = true
    @AppStorage("showDrawingHints") private var showDrawingHints: Bool = true
    @AppStorage("defaultDesignDestination") private var defaultDesignDestination: String = DesignDestination.figma.rawValue
    @AppStorage(ShadcnThemeStorage.baseColorKey)
    private var shadcnBaseColor: String = ShadcnThemeStorage.defaultBaseColor.rawValue
    @AppStorage(ShadcnThemeStorage.appearanceKey)
    private var themeAppearance: String = ShadcnThemeStorage.defaultAppearance.rawValue

    @EnvironmentObject private var appState: AppState

    @State private var isConnectingFigma = false
    @State private var figmaError: String?

    private let availableModels = [
        "gemini-3.1-pro-preview",
        "gemini-2.5-pro-preview-06-05",
        "gemini-2.5-flash-preview-05-20"
    ]

    var body: some View {
        NavigationStack {
            Form {
                apiKeySection
                modelSection
                behaviorSection
                appearanceSection
                designSystemSection
                designToolsSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAPIKey()
                        dismiss()
                    }
                }
            }
            .onAppear {
                apiKey = KeychainHelper.loadAPIKey() ?? ""
            }
            .sheet(isPresented: $showingDesignSystem) {
                DesignSystemSetupView()
            }
        }
    }

    // MARK: - API Key

    @ViewBuilder
    private var apiKeySection: some View {
        Section {
            SecureField("Gemini API Key", text: $apiKey)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !apiKey.isEmpty {
                Button("Clear API Key", role: .destructive) {
                    apiKey = ""
                    KeychainHelper.deleteAPIKey()
                }
            }
        } header: {
            Text("API Key")
        } footer: {
            Text("Your API key is stored securely in the device keychain. Get a key from Google AI Studio (aistudio.google.com).")
        }
    }

    // MARK: - Model Picker

    @ViewBuilder
    private var modelSection: some View {
        Section("Model") {
            Picker("Model", selection: $selectedModel) {
                ForEach(availableModels, id: \.self) { model in
                    Text(displayName(for: model))
                        .tag(model)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    // MARK: - Behavior

    @ViewBuilder
    private var behaviorSection: some View {
        Section {
            Toggle("Auto-convert after pause", isOn: $autoConvertEnabled)
            Toggle("Drawing hints", isOn: $showDrawingHints)
        } header: {
            Text("Behavior")
        } footer: {
            Text("Auto-convert sends your sketch to the AI after a 3-second drawing pause. Drawing hints show subtle badges guessing what component each shape might become.")
        }
    }

    // MARK: - Appearance

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            Picker("Base color", selection: $shadcnBaseColor) {
                ForEach(ShadcnBaseColor.allCases) { color in
                    Text(color.displayName).tag(color.rawValue)
                }
            }
            Picker("Mode", selection: $themeAppearance) {
                ForEach(ThemeAppearance.allCases) { appearance in
                    Text(appearance.displayName).tag(appearance.rawValue)
                }
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Theme tokens are injected into the rendered preview at runtime — switching here re-themes existing previews without re-prompting the AI.")
        }
    }

    // MARK: - Design System

    @ViewBuilder
    private var designSystemSection: some View {
        Section {
            Button {
                showingDesignSystem = true
            } label: {
                HStack {
                    Label("Global design system", systemImage: "square.on.square.dashed")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if let project = appState.currentProject {
                Button {
                    showingProjectDesign = true
                } label: {
                    HStack {
                        Label("This project's design", systemImage: "doc.badge.gearshape")
                        Spacer()
                        if project.usesCustomDesignSystem {
                            Text(project.customPresetName ?? "Custom")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Inherits")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingProjectDesign) {
                    ProjectDesignSystemView(project: project)
                }
            }
        } header: {
            Text("Design System")
        } footer: {
            Text("Pick a curated preset, attach a DESIGN.md, link a repo, or paste notes — the conversion prompt will use this context. Each project can override the global default.")
        }
    }

    // MARK: - Design Tools

    @ViewBuilder
    private var designToolsSection: some View {
        Section {
            HStack {
                Label("Figma", systemImage: "rectangle.connected.to.line.below")
                Spacer()
                if isConnectingFigma {
                    ProgressView().controlSize(.small)
                } else if appState.figmaConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                    Button("Disconnect", role: .destructive) {
                        appState.disconnectFigma()
                        figmaError = nil
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button("Connect") {
                        connectFigma()
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let figmaError = figmaError {
                Label(figmaError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Picker("Default destination", selection: $defaultDesignDestination) {
                ForEach(DesignDestination.allCases.filter(\.isAvailable)) { destination in
                    Text(destination.displayName).tag(destination.rawValue)
                }
            }
        } header: {
            Text("Design Tools")
        } footer: {
            Text("Connect a design tool to send your sketch and generated code into a real, editable design. Figma uses its remote MCP server (mcp.figma.com).")
        }
    }

    private func connectFigma() {
        isConnectingFigma = true
        figmaError = nil
        Task {
            do {
                try await appState.connectFigma()
            } catch {
                figmaError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isConnectingFigma = false
        }
    }

    // MARK: - Helpers

    private func saveAPIKey() {
        guard !apiKey.isEmpty else { return }
        KeychainHelper.saveAPIKey(apiKey)
    }

    private func displayName(for model: String) -> String {
        switch model {
        case "gemini-3.1-pro-preview":
            return "Gemini 3.1 Pro (Recommended)"
        case "gemini-2.5-pro-preview-06-05":
            return "Gemini 2.5 Pro"
        case "gemini-2.5-flash-preview-05-20":
            return "Gemini 2.5 Flash"
        default:
            return model
        }
    }

}
