import ScribeXCore
import SwiftUI

/// A row of templates, each opening a new document with its source.
struct TemplateTiles: View {
    @Environment(Engine.self) private var engine
    @Environment(\.newDocument) private var newDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start from a template").smallCaps()
            HStack(spacing: 12) {
                ForEach(templates) { template in
                    Button { newDocument { TexDocument(text: template.source) } } label: {
                        VStack(spacing: 8) {
                            TemplateSketch(name: template.name)
                                .frame(maxWidth: .infinity, minHeight: 100)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))
                            Text(template.name)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(template.note)
                }
            }
            .disabled(engine.locked)
        }
    }
}

/// A template's first page in miniature: a sheet of paper with grey lines where
/// its type would be.
private struct TemplateSketch: View {
    let name: String

    var body: some View {
        let slides = name == "Beamer"
        VStack(alignment: .leading, spacing: 3) {
            if slides {
                Rectangle().fill(.paperEdge).frame(height: 12)
            }
            ForEach(lines.indices, id: \.self) { i in
                Rectangle().frame(width: lines[i], height: i == 0 && !slides ? 2.5 : 1)
            }
        }
        .foregroundStyle(Color.paperEdge.opacity(0.5))
        .padding(slides ? 0 : 8)
        .frame(width: slides ? 76 : 57, height: slides ? 57 : 76, alignment: .topLeading)
        .background(.paper)
        .shadow(radius: 3, y: 2)
    }

    private var lines: [CGFloat] {
        switch name {
        case "Letter": [16, 20, 0, 40, 40, 40, 24]
        case "Thesis": [30, 20, 0, 14]
        case "Beamer": [36, 28, 32]
        default: [22, 0, 40, 40, 40, 28, 18, 40, 33]
        }
    }
}

#Preview {
    TemplateTiles().environment(Engine.preview).frame(width: 472).padding(40).scribeStyle()
}
