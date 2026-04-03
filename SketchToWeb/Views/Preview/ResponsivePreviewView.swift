import SwiftUI
import WebKit

/// Wraps a WKWebView inside a simulated device frame, letting the user preview
/// generated UI at phone, tablet, and desktop viewport sizes.
struct ResponsivePreviewView: View {
    let htmlContent: String

    @State private var selectedDevice: DevicePreset = .tablet

    // MARK: - Device Presets

    enum DevicePreset: String, CaseIterable, Identifiable {
        case phone
        case tablet
        case desktop

        var id: String { rawValue }

        var size: CGSize {
            switch self {
            case .phone:   return CGSize(width: 390, height: 844)
            case .tablet:  return CGSize(width: 768, height: 1024)
            case .desktop: return CGSize(width: 1280, height: 800)
            }
        }

        var label: String {
            switch self {
            case .phone:   return "Phone"
            case .tablet:  return "Tablet"
            case .desktop: return "Desktop"
            }
        }

        var iconName: String {
            switch self {
            case .phone:   return "iphone"
            case .tablet:  return "ipad"
            case .desktop: return "desktopcomputer"
            }
        }

        var viewportWidth: Int {
            Int(size.width)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            devicePicker
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            GeometryReader { geometry in
                let scale = scaleFactor(
                    deviceSize: selectedDevice.size,
                    availableSize: geometry.size
                )

                VStack(spacing: 8) {
                    Spacer()

                    deviceFrame(scale: scale)

                    dimensionLabel

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Subviews

    private var devicePicker: some View {
        Picker("Device", selection: $selectedDevice) {
            ForEach(DevicePreset.allCases) { preset in
                Label(preset.label, systemImage: preset.iconName)
                    .tag(preset)
            }
        }
        .pickerStyle(.segmented)
    }

    private func deviceFrame(scale: CGFloat) -> some View {
        ResponsiveWebView(
            htmlContent: htmlContent,
            viewportWidth: selectedDevice.viewportWidth
        )
        .frame(
            width: selectedDevice.size.width,
            height: selectedDevice.size.height
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .scaleEffect(scale)
        .frame(
            width: selectedDevice.size.width * scale,
            height: selectedDevice.size.height * scale
        )
    }

    private var dimensionLabel: some View {
        Text("\(Int(selectedDevice.size.width)) × \(Int(selectedDevice.size.height))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    // MARK: - Helpers

    /// Returns a scale factor (≤ 1) that fits the device frame inside the
    /// available space with some padding.
    private func scaleFactor(deviceSize: CGSize, availableSize: CGSize) -> CGFloat {
        let padding: CGFloat = 32
        let usable = CGSize(
            width: max(1, availableSize.width - padding),
            height: max(1, availableSize.height - padding - 30) // extra room for dimension label
        )
        let scaleX = usable.width / deviceSize.width
        let scaleY = usable.height / deviceSize.height
        return min(min(scaleX, scaleY), 1.0)
    }
}

// MARK: - ResponsiveWebView (UIViewRepresentable)

/// A WKWebView wrapper that injects a viewport width override whenever the
/// selected device preset changes.
private struct ResponsiveWebView: UIViewRepresentable {
    let htmlContent: String
    let viewportWidth: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = true
        webView.scrollView.bounces = true
        webView.backgroundColor = .systemBackground
        webView.allowsLinkPreview = false

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let contentChanged = context.coordinator.lastLoadedContent != htmlContent
        let viewportChanged = context.coordinator.lastViewportWidth != viewportWidth

        if contentChanged {
            context.coordinator.lastLoadedContent = htmlContent
            context.coordinator.lastViewportWidth = viewportWidth
            webView.loadHTMLString(htmlContent, baseURL: nil)
            // After the page loads, set the viewport width.
            injectViewport(into: webView)
        } else if viewportChanged {
            context.coordinator.lastViewportWidth = viewportWidth
            injectViewport(into: webView)
        }
    }

    private func injectViewport(into webView: WKWebView) {
        let js = """
        (function() {
            var meta = document.querySelector('meta[name=viewport]');
            if (meta) {
                meta.content = 'width=\(viewportWidth)';
            } else {
                meta = document.createElement('meta');
                meta.name = 'viewport';
                meta.content = 'width=\(viewportWidth)';
                document.head.appendChild(meta);
            }
        })();
        """
        // Small delay to let initial load finish when content just changed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: - Coordinator

    final class Coordinator {
        var lastLoadedContent: String?
        var lastViewportWidth: Int?
    }
}
