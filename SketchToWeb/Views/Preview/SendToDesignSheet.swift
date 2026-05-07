import SwiftUI

/// Modal sheet that drives a `DesignExportPipeline` run to completion, showing
/// streaming progress and surfacing the resulting design URL to open.
struct SendToDesignSheet: View {

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage("defaultDesignDestination") private var defaultDesignDestinationRaw: String = DesignDestination.figma.rawValue

    @State private var userInstruction: String = ""
    @State private var hasStarted = false

    private var destination: DesignDestination {
        DesignDestination(rawValue: defaultDesignDestinationRaw) ?? .figma
    }

    var body: some View {
        NavigationStack {
            Form {
                destinationSection
                instructionSection
                statusSection
            }
            .navigationTitle("Send to \(destination.displayName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        appState.resetDesignExportState()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(actionButtonTitle) {
                        primaryAction()
                    }
                    .disabled(actionButtonDisabled)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    @ViewBuilder
    private var destinationSection: some View {
        Section {
            HStack {
                Label(destination.displayName, systemImage: destination.systemImageName)
                Spacer()
                if appState.figmaConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Label("Not connected", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }
        } footer: {
            if !appState.figmaConnected {
                Text("Connect Figma in Settings to enable export.")
            }
        }
    }

    @ViewBuilder
    private var instructionSection: some View {
        Section("Optional note for the model") {
            TextField("e.g. group everything into a single Login frame", text: $userInstruction, axis: .vertical)
                .lineLimit(2...4)
                .disabled(isInProgress)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("Status") {
            switch appState.designExportState {
            case nil:
                Text("Ready to send.")
                    .foregroundStyle(.secondary)

            case .connecting:
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to \(destination.displayName)…")
                }

            case .working(let step):
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(step)
                }

            case .completed(let url):
                Label("Done!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let url = url {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open in \(destination.displayName)", systemImage: "arrow.up.right.square")
                    }
                }

            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Action Wiring

    private var isInProgress: Bool {
        switch appState.designExportState {
        case .connecting, .working:
            return true
        default:
            return false
        }
    }

    private var actionButtonTitle: String {
        switch appState.designExportState {
        case .completed, .failed:
            return "Done"
        default:
            return hasStarted ? "Sending…" : "Send"
        }
    }

    private var actionButtonDisabled: Bool {
        switch appState.designExportState {
        case .completed, .failed:
            return false
        default:
            return !appState.figmaConnected || isInProgress || appState.generatedResult == nil
        }
    }

    private func primaryAction() {
        switch appState.designExportState {
        case .completed, .failed:
            appState.resetDesignExportState()
            dismiss()
        default:
            hasStarted = true
            appState.exportToDesignTool(
                destination: destination,
                userInstruction: userInstruction.isEmpty ? nil : userInstruction
            )
        }
    }
}
