import AppKit
import ScribeXCore
import SwiftUI

struct AppCommand: Identifiable {
    let id: String
    let title: String
    var hint: String?
    var words: [String] = []
    var disabled = false
    let run: () -> Void
}

extension Session {
    var commands: [AppCommand] {
        [
            // File commands go to the document system, as the menu items do.
            AppCommand(id: "save", title: "Save", hint: "⌘S", words: ["write", "disk"]) { NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil) },
            AppCommand(id: "saveas", title: "Save as…", hint: "⇧⌘S", words: ["copy", "rename"]) { NSApp.sendAction(#selector(NSDocument.saveAs(_:)), to: nil, from: nil) },
            AppCommand(id: "export", title: "Export as PDF…", hint: "⌘E", words: ["pdf", "save", "print"], disabled: preview == nil) { [unowned self] in exportOpen = true },
            AppCommand(id: "open", title: "Open…", hint: "⌘O", words: ["file", "document"], disabled: engine.locked) { NSDocumentController.shared.openDocument(nil) },
            AppCommand(id: "new", title: "New document", hint: "⌘N", words: ["blank", "start"], disabled: engine.locked) { NSDocumentController.shared.newDocument(nil) },
            AppCommand(id: "build", title: "Build now", hint: "⌘R", words: ["set", "compile", "typeset", "rebuild"], disabled: busy) { [unowned self] in build() },
            AppCommand(id: "live", title: autoBuild ? "Stop building as I type" : "Build as I type", words: ["live", "auto", "rebuild", "debounce", "set"]) { [unowned self] in autoBuild.toggle() },
            AppCommand(id: "offline", title: offline ? "Allow the network" : "Refuse the network", words: ["offline", "online", "cache"]) { [unowned self] in toggleOffline() },
            AppCommand(id: "zoomin", title: "Zoom in on the preview", hint: "⌘+", words: ["enlarge", "bigger", "proof"]) { [unowned self] in zoom(by: 1) },
            AppCommand(id: "zoomout", title: "Zoom out of the preview", hint: "⌘−", words: ["reduce", "smaller", "proof"]) { [unowned self] in zoom(by: -1) },
            AppCommand(id: "zoomfit", title: "Fit the preview to width", hint: "⌘0", words: ["zoom", "fit", "width", "reset", "proof"]) { [unowned self] in zoom = .fit },
            AppCommand(id: "marks", title: "Show issues", words: ["errors", "warnings", "problems", "marks"], disabled: visible.isEmpty) { [unowned self] in rightPane = .marks },
            AppCommand(id: "presslog", title: pressOpen ? "Hide the press log" : "Show the press log", words: ["log", "tex", "passes"]) { [unowned self] in pressOpen.toggle() },
            AppCommand(id: "prime", title: "Download the LaTeX essentials", words: ["prime", "cache", "offline", "packages", "fonts", "setup"], disabled: engine.cache == .downloading) { [unowned self] in setUp() },
        ]
    }
}

struct PaletteRow: Identifiable {
    var id: String
    var title: String
    var preview: String?
    var hint: String?
    var text: String?
    var score: Double
    var command: AppCommand?

    static func rows(for query: String, commands: [AppCommand], hasSelection: Bool) -> [PaletteRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cmds = commands.filter { !$0.disabled }

        if q.isEmpty {
            return cmds.map { PaletteRow(id: $0.id, title: $0.title, hint: $0.hint, score: 1, command: $0) }
        }

        // Same tokenizer as the snippet matcher, so filler words ("a", "put",
        // "here") cannot drag in every command that happens to contain the letter.
        let words = tokenize(q)
        let scored: [PaletteRow] = cmds.compactMap { c in
            let hay = tokenize(([c.title] + c.words).joined(separator: " "))
            // Match whole words or their prefixes, never substrings — otherwise
            // "as" finds "Save as…" by way of the middle of a word.
            let hits = words.filter { w in hay.contains { $0.hasPrefix(w) || w.hasPrefix($0) } }.count
            let score = words.isEmpty ? 0 : Double(hits) / Double(words.count)
            guard score > 0 else { return nil }
            // Commands and snippets share a scale; an exact command match should
            // outrank a loose snippet match, but never a precise one.
            return PaletteRow(id: c.id, title: c.title, hint: c.hint, score: score * 0.95, command: c)
        }

        let snippets = suggest(q, hasSelection: hasSelection, limit: 6).map {
            PaletteRow(id: $0.id, title: $0.title, preview: $0.preview, hint: $0.hint, text: $0.text, score: $0.score)
        }
        // Stable on ties, so snippets keep their own order ahead of commands.
        return Array((snippets + scored).enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .map(\.element)
            .prefix(7))
    }
}

/// ⌘K: describe a snippet in plain English, or name a command. A sheet over
/// the document window.
struct PaletteView: View {
    let model: Session
    @State private var query = ""
    @State private var active: String?
    @FocusState private var focused: Bool

    var body: some View {
        let rows = PaletteRow.rows(for: query, commands: model.commands, hasSelection: !model.selection.isEmpty)

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
        .onAppear {
            focused = true
            active = rows.first?.id
        }
        .onChange(of: query) { active = PaletteRow.rows(for: query, commands: model.commands, hasSelection: !model.selection.isEmpty).first?.id }
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
        model.paletteOpen = false
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
    PaletteView(model: .preview())
}
