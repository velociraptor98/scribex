import ScribeXCore
import SwiftUI

/// The document's headings, each a jump to its line, with a tally beneath.
struct Contents: View {
    let model: Session
    @Binding var isOpen: Bool

    var body: some View {
        let sections = model.sections
        // Indent relative to the shallowest heading present, so an article whose
        // top level is \section is not pushed in by levels it never uses.
        let base = sections.map(\.level).min() ?? 0
        let tally = model.tally

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Contents").smallCaps()
                Spacer()
                Button("Close", systemImage: "xmark") { isOpen = false }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .help("Hide the contents (⌃⌘S)")
            }
            .padding(16)
            List(sections.indices, id: \.self) { i in
                let entry = sections[i]
                Button { model.editor.goto(entry.line) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(entry.number).foregroundStyle(.tertiary).monospacedDigit()
                        Text(entry.title.isEmpty ? "Untitled" : entry.title).italic(entry.title.isEmpty)
                    }
                    .padding(.leading, CGFloat(entry.level - base) * 12)
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Line \(entry.line)")
            }
            .scrollContentBackground(.hidden)
            .overlay { if sections.isEmpty { Text("No sections yet").italic().foregroundStyle(.secondary) } }
            Text("\(plural(tally.sections, "section")) · \(plural(tally.equations, "equation"))\n\(plural(tally.citations, "citation"))")
                .font(Fonts.text(11.5)).foregroundStyle(.secondary).padding(16)
        }
    }

    private func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
}

#Preview {
    Contents(model: .preview(), isOpen: .constant(true)).scribeStyle().frame(width: 200, height: 600)
}
