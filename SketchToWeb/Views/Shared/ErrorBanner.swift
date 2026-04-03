import SwiftUI

/// A red-tinted error banner that slides in from the top of the screen.
/// Includes a dismiss button and auto-dismisses after 5 seconds.
struct ErrorBanner: View {

    let message: String
    var onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                    .font(.title3)

                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.8))
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.gradient)
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isVisible = false
        }
        // Allow the exit animation to finish before calling onDismiss.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }

    private func scheduleAutoDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            guard isVisible else { return }
            dismiss()
        }
    }
}

// MARK: - Initializer with onAppear scheduling

extension ErrorBanner {
    /// Creates the banner and starts the auto-dismiss timer once it appears.
    init(message: String, onDismiss: @escaping () -> Void, autoShow: Bool = true) {
        self.message = message
        self.onDismiss = onDismiss
        // _isVisible is set via onAppear below; default to the autoShow value.
        self._isVisible = State(initialValue: autoShow)
    }
}

// MARK: - View Modifier

extension View {
    /// Attaches an error banner to the top of the view. Pass `nil` to hide.
    @ViewBuilder
    func errorBanner(_ message: String?, onDismiss: @escaping () -> Void) -> some View {
        self.overlay(alignment: .top) {
            if let message {
                ErrorBanner(message: message, onDismiss: onDismiss)
                    .onAppear {
                        // Schedule auto-dismiss when the banner appears.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            onDismiss()
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: message == nil)
    }
}
