import ScribeXCore
import SwiftUI

/// The document's headings, each a jump to its line, with a tally beneath.
/// The section the cursor is in stays selected, as a sidebar shows where you are.
struct Contents: View {
    let model: Session
    /// The editor's cursor line, 1-based.
    let caretLine: Int

    var body: some View {
        let sections = model.outline.sections
        // Indent relative to the shallowest heading present, so an article whose
        // top level is \section is not pushed in by levels it never uses.
        let base = sections.map(\.level).min() ?? 0
        let tally = model.outline.tally

        VStack(alignment: .leading, spacing: 0) {
            Text("Contents").smallCaps().padding(16)
            // Choosing a section moves the cursor there, which keeps it selected.
            let current = Binding<Int?>(
                get: { sections.lastIndex { $0.line <= caretLine } },
                set: { if let i = $0 { model.editor.goto(sections[i].line) } }
            )
            List(sections.indices, id: \.self, selection: current) { i in
                let entry = sections[i]
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(entry.number).foregroundStyle(.tertiary).monospacedDigit()
                    Text(entry.title.isEmpty ? "Untitled" : entry.title).italic(entry.title.isEmpty)
                }
                .padding(.leading, CGFloat(entry.level - base) * 12)
                .lineLimit(1)
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
    Contents(model: .preview(), caretLine: 1).scribeStyle().frame(width: 200, height: 600)
}
