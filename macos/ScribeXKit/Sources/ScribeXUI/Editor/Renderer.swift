import ScribeXCore
import SwiftUI

/// How the preview is zoomed: to the column's width, or to a set scale.
/// `scale` is what is on screen either way, so zooming steps from there.
struct Zoom: Equatable {
    static let range = 0.25...4.0
    static let steps = [0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4]

    var fit = true
    var scale = 1.0

    /// Fit width can leave the scale between stops; this goes to the next one.
    mutating func step(_ direction: Int) {
        let next = direction > 0
            ? Self.steps.first { $0 > scale + 0.005 }
            : Self.steps.last { $0 < scale - 0.005 }
        fit = false
        scale = next ?? (direction > 0 ? Self.range.upperBound : Self.range.lowerBound)
    }
}

/// The typeset pages: Export above, page count, zoom and build status below.
struct Renderer: View {
    let model: Session
    @Binding var zoom: Zoom
    var export: () -> Void
    /// Reported by the PDF view as it scrolls; nothing else needs them.
    @State private var pages = 0
    @State private var page = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Preview").smallCaps()
                Spacer()
                Button("Export PDF…", action: export)
                    .disabled(model.preview == nil || model.busy)
            }
            .padding(12)

            PreviewView(preview: model.preview, zoom: zoom,
                        onScale: { zoom.scale = $0 }, onPages: { pages = $0 }, onPage: { page = $0 })
                .overlay { if model.preview == nil { Text("Nothing built yet").italic().foregroundStyle(.secondary) } }
                .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                Text(pages > 0 ? "Page \(min(page, pages)) of \(pages)" : "No preview yet")
                Spacer()
                zoomControls
                Spacer()
                Text(model.status).lineLimit(1).opacity(model.busy ? 0.6 : 1)
            }
            .font(Fonts.text(11.5))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .controlSize(.small)
            .padding(12)
        }
        .background(.sunken)
    }

    private var zoomControls: some View {
        HStack(spacing: 6) {
            ControlGroup {
                Button("Zoom Out", systemImage: "minus") { zoom.step(-1) }.disabled(zoom.scale <= Zoom.range.lowerBound)
                Button("Zoom In", systemImage: "plus") { zoom.step(1) }.disabled(zoom.scale >= Zoom.range.upperBound)
            }
            .fixedSize()
            Button("\(Int((zoom.scale * 100).rounded()))%") { zoom = Zoom(fit: false, scale: 1) }
                .buttonStyle(.borderless)
                .help("Actual size")
            Toggle("Fit", isOn: $zoom.fit)
                .toggleStyle(.button)
                .help("Fit to width (⌘0)")
        }
    }
}

#Preview {
    @Previewable @State var zoom = Zoom()
    Renderer(model: .preview(), zoom: $zoom, export: {}).scribeStyle().frame(width: 560, height: 700)
}
