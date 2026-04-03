import SwiftUI
import UIKit

/// Displays generated source code with basic syntax highlighting,
/// a monospaced font, and a copy-to-clipboard button.
struct CodePreviewView: View {
    let code: String
    let language: String

    @State private var showCopiedToast = false
    @State private var highlightedResult: AttributedString?

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView([.horizontal, .vertical]) {
                Text(highlightedResult ?? AttributedString(code))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(red: 0x1e / 255, green: 0x1e / 255, blue: 0x2e / 255))

            // Copy button
            Button {
                UIPasteboard.general.string = code
                withAnimation {
                    showCopiedToast = true
                }
                // Dismiss toast after a short delay.
                DispatchQueue.main.asyncAfter(deadline: .now() + TimingConstants.toastDuration) {
                    withAnimation {
                        showCopiedToast = false
                    }
                }
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.body)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(12)

            // "Copied!" toast
            if showCopiedToast {
                Text("Copied!")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.85), in: Capsule())
                    .padding(.top, 52)
                    .padding(.trailing, 12)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .onChange(of: code) { _, newCode in
            highlightedResult = Self.highlight(newCode)
        }
        .onAppear {
            highlightedResult = Self.highlight(code)
        }
    }

    // MARK: - Syntax Highlighting

    private static func highlight(_ code: String) -> AttributedString {
        var result = AttributedString(code)

        // Base style: light text on dark background.
        result.foregroundColor = Color(red: 0.81, green: 0.83, blue: 0.90)

        highlightPattern(&result, pattern: #"//.*"#, color: .gray)                        // Line comments
        highlightPattern(&result, pattern: #"/\*[\s\S]*?\*/"#, color: .gray)               // Block comments
        highlightPattern(&result, pattern: #""[^"\\]*(?:\\.[^"\\]*)*""#, color: .red)       // Double-quoted strings
        highlightPattern(&result, pattern: #"'[^'\\]*(?:\\.[^'\\]*)*'"#, color: .green)     // Single-quoted strings
        highlightPattern(&result, pattern: #"`[^`]*`"#, color: .green)                     // Template literals
        highlightPattern(&result, pattern: #"</?[A-Z][A-Za-z0-9.]*"#, color: .blue)        // JSX tags
        highlightKeywords(&result)

        return result
    }

    /// Highlights JavaScript/JSX keywords in purple.
    private static func highlightKeywords(_ attributed: inout AttributedString) {
        let plain = String(attributed.characters)
        let nsRange = NSRange(plain.startIndex..., in: plain)

        guard let regex = try? NSRegularExpression(pattern: #"\b(?:import|export|function|const|let|var|return|from|default|if|else|class|extends|new|this|async|await|try|catch|throw|typeof|interface|type)\b"#) else { return }

        for match in regex.matches(in: plain, range: nsRange) {
            guard let swiftRange = Range(match.range, in: plain),
                  let attrRange = Range(swiftRange, in: attributed) else { continue }
            attributed[attrRange].foregroundColor = .purple
        }
    }

    /// Applies a foreground color to all matches of `pattern` in the attributed string.
    private static func highlightPattern(_ attributed: inout AttributedString, pattern: String, color: Color) {
        let plain = String(attributed.characters)
        let nsRange = NSRange(plain.startIndex..., in: plain)

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        for match in regex.matches(in: plain, range: nsRange) {
            guard let swiftRange = Range(match.range, in: plain),
                  let attrRange = Range(swiftRange, in: attributed) else { continue }
            attributed[attrRange].foregroundColor = color
        }
    }
}
