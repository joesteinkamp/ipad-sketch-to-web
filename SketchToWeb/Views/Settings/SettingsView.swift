import SwiftUI

/// A settings sheet for configuring the Gemini API connection and model selection.
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var isTesting = false

    @AppStorage("selectedModel") private var selectedModel: String = "gemini-3.1-pro-preview"
    @AppStorage("autoConvertEnabled") private var autoConvertEnabled: Bool = true
    @AppStorage("showDrawingHints") private var showDrawingHints: Bool = true
    @AppStorage("defaultDesignDestination") private var defaultDesignDestination: String = DesignDestination.figma.rawValue

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
                designToolsSection
                connectionSection
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
                    connectionStatus = .unknown
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

    // MARK: - Connection Test

    @ViewBuilder
    private var connectionSection: some View {
        Section("Connection") {
            HStack {
                Button {
                    testConnection()
                } label: {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                        Text("Testing...")
                    } else {
                        Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                .disabled(apiKey.isEmpty || isTesting)

                Spacer()

                statusIndicator
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch connectionStatus {
        case .unknown:
            EmptyView()
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline)
        case .error(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
                .lineLimit(2)
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

    private func testConnection() {
        saveAPIKey()
        isTesting = true
        connectionStatus = .unknown

        Task {
            do {
                try await performTestRequest()
                connectionStatus = .connected
            } catch {
                connectionStatus = .error(error.localizedDescription)
            }
            isTesting = false
        }
    }

    /// Sends a minimal generateContent request to the Gemini API to verify the key is valid.
    private func performTestRequest() async throws {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(selectedModel):generateContent?key=\(apiKey)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "contents": [
                ["parts": [["text": "Hi"]]]
            ],
            "generationConfig": [
                "maxOutputTokens": 16
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "SettingsView",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
            )
        }
    }

    // MARK: - Connection Status

    private enum ConnectionStatus {
        case unknown
        case connected
        case error(String)
    }
}
