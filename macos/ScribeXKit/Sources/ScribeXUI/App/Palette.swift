import AppKit
import ScribeXCore
import SwiftUI

struct PaletteRow: Identifiable {
    var id: String
    var title: String
    var preview: String?
    var hint: String?
    var text: String?
    var command: Command?

    /// Snippets and commands in one list, both ranked by `relevance`.
    static func rows(for query: String, commands: [Command], hasSelection: Bool) -> [PaletteRow] {
        let cmds = commands.filter { $0.inPalette && $0.isEnabled }
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return cmds.map { PaletteRow(id: $0.id, title: $0.label, hint: $0.hint, command: $0) }
        }

        let words = tokenize(query)
        let snippetRows = suggest(query, hasSelection: hasSelection).map {
            (row: PaletteRow(id: $0.id, title: $0.title, preview: $0.preview, hint: $0.hint, text: $0.text),
             score: relevance(of: $0.words, to: words))
        }
        // Whole words and their prefixes, as for snippets, never substrings:
        // otherwise "as" would find "Save As…" by way of the middle of a word.
        let commandRows = cmds.map {
            (row: PaletteRow(id: $0.id, title: $0.label, hint: $0.hint, command: $0),
             score: relevance(of: tokenize(([$0.title] + $0.words).joined(separator: " ")), to: words))
        }
        // On a tie the earlier row wins: snippets in their own order, then commands.
        return (snippetRows + commandRows).enumerated()
            .filter { $0.element.score > 0 }
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .prefix(7)
            .map(\.element.row)
    }
}

/// ⌘K: describe a snippet in plain English, or name a command. A sheet over
/// the document window.
struct Palette: View {
    let model: Session
    /// Built by the window, which holds the state its commands change.
    let commands: [Command]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var active: String?
    @FocusState private var focused: Bool

    init(model: Session, commands: [Command]) {
        self.model = model
        self.commands = commands
        // The first row is selected from the start. Selecting it in onAppear
        // changes the list's selection while the list is first being built,
        // which trips an assertion inside SwiftUI's List (seen in the canvas).
        _active = State(initialValue: PaletteRow.rows(for: "", commands: commands, hasSelection: false).first?.id)
    }

    var body: some View {
        let rows = PaletteRow.rows(for: query, commands: commands, hasSelection: !model.editor.selectedText.isEmpty)

        VStack(spacing: 0) {
            TextField("Describe what to insert, or name a command", text: $query)
                .textFieldStyle(.plain)
                .font(Fonts.text(18))
                .focused($focused)
                .padding(20)
                // The field keeps focus; the arrows move through the list below it.
                .onKeyPress(.upArrow) { move(-1, in: rows); return .handled }
                .onKeyPress(.downArrow) { move(1, in: rows); return .handled }
                .onSubmit { choose(rows.first { $0.id == active } ?? rows.first) }
            Divider()
            if rows.isEmpty {
                Text("Nothing matches. Try naming what you want — \u{201C}a bulleted list\u{201D}, \u{201C}aligned equations\u{201D}.")
                    .italic().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            } else {
                List(rows, selection: $active) { row in
                    PaletteItem(row: row)
                }
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { ids in
                    choose(rows.first { ids.contains($0.id) })
                }
                .frame(height: min(CGFloat(rows.count) * 50 + 12, 360))
            }
        }
        .frame(width: 600)
        .scribeStyle()
        .onAppear { focused = true }
        .onChange(of: query) { active = PaletteRow.rows(for: query, commands: commands, hasSelection: !model.editor.selectedText.isEmpty).first?.id }
        .onExitCommand(perform: close)
    }

    private func move(_ by: Int, in rows: [PaletteRow]) {
        let index = rows.firstIndex { $0.id == active } ?? -1
        active = rows[max(0, min(rows.count - 1, index + by))].id
    }

    private func choose(_ row: PaletteRow?) {
        guard let row else { return }
        close()
        if let command = row.command {
            command.run()
        } else if let text = row.text {
            model.insert(text)
        }
    }

    private func close() {
        dismiss()
        model.editor.focus()
    }
}

private struct PaletteItem: View {
    let row: PaletteRow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                if let preview = row.preview {
                    Text(preview).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer()
            if let hint = row.hint {
                Text(hint).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let session = Session.preview()
    Palette(model: session, commands: Command.all(Command.Focus(session: session), engine: session.engine))
}
