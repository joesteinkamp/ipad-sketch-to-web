import SwiftUI
import PencilKit

/// A sheet presenting a grid of pre-built wireframe templates that users can select
/// to populate the canvas with a starting layout they can then refine with Apple Pencil.
struct TemplatePickerSheet: View {

    @Environment(\.dismiss) private var dismiss

    /// Called when the user selects a template. The generated PKDrawing replaces the canvas.
    var onTemplateSelected: (PKDrawing) -> Void

    /// The canvas size used to generate properly scaled template drawings.
    var canvasSize: CGSize

    private let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 20)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(SketchTemplates.all) { template in
                        TemplateCard(template: template, canvasSize: canvasSize) {
                            let drawing = template.generator(canvasSize)
                            onTemplateSelected(drawing)
                            dismiss()
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Template Card

/// A card that shows a template name, icon, and a small preview of the drawing.
private struct TemplateCard: View {

    let template: SketchTemplates.Template
    let canvasSize: CGSize
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                // Preview thumbnail
                templatePreview
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Image(systemName: template.iconName)
                        .foregroundStyle(.secondary)
                    Text(template.name)
                        .font(.headline)
                }
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    /// Renders the template PKDrawing as a small image preview.
    @ViewBuilder
    private var templatePreview: some View {
        let previewSize = CGSize(width: 1024, height: 768)
        let drawing = template.generator(previewSize)
        let image = DrawingExporter.exportAsImage(drawing, canvasSize: previewSize)

        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
    }
}
