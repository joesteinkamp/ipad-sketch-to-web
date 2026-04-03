import SwiftUI

/// A full-screen semi-transparent overlay with a progress indicator and label.
/// Animates in and out with an opacity transition.
struct LoadingOverlay: View {

    var message: String = "Converting sketch..."

    @State private var isVisible = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .tint(.white)

                Text(message)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.25)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Conditional Modifier

extension View {
    /// Presents a loading overlay when `isPresented` is true.
    @ViewBuilder
    func loadingOverlay(isPresented: Bool, message: String = "Converting sketch...") -> some View {
        self.overlay {
            if isPresented {
                LoadingOverlay(message: message)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
    }
}
