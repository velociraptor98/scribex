import ScribeXCore
import SwiftUI

/// The typeset pages: Export above, page count, zoom and build status below.
struct Renderer: View {
    let model: Session
    /// Reported by the PDF view as it scrolls; nothing else needs them.
    @State private var pages = 0
    @State private var page = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Preview").smallCaps()
                Spacer()
                Button("Export PDF…", action: model.requestExport)
                    .disabled(model.preview == nil || model.busy)
            }
            .padding(12)

            PreviewView(preview: model.preview, zoom: model.zoom,
                        onScale: { model.scale = $0 }, onPages: { pages = $0 }, onPage: { page = $0 })
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
                Button("Zoom Out", systemImage: "minus") { model.zoom(by: -1) }.disabled(model.scale <= Session.minZoom)
                Button("Zoom In", systemImage: "plus") { model.zoom(by: 1) }.disabled(model.scale >= Session.maxZoom)
            }
            .fixedSize()
            Button("\(Int((model.scale * 100).rounded()))%") { model.zoom = .scale(1) }
                .buttonStyle(.borderless)
                .help("Actual size")
            Toggle("Fit", isOn: Binding(get: { model.zoom == .fit }, set: { model.zoom = $0 ? .fit : .scale(model.scale) }))
                .toggleStyle(.button)
                .help("Fit to width (⌘0)")
        }
    }
}

#Preview {
    Renderer(model: .preview()).scribeStyle().frame(width: 560, height: 700)
}
