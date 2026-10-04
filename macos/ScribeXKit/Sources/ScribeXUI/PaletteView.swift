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

extension AppModel {
    var commands: [AppCommand] {
        [
            AppCommand(id: "save", title: "Save", hint: "⌘S", words: ["write", "disk"], disabled: !dirty && path != nil) { [unowned self] in save() },
            AppCommand(id: "saveas", title: "Save as…", hint: "⇧⌘S", words: ["copy", "rename"]) { [unowned self] in save(as: true) },
            AppCommand(id: "export", title: "Export as PDF…", hint: "⌘E", words: ["pdf", "save", "print"], disabled: preview == nil) { [unowned self] in exportOpen = true },
            AppCommand(id: "open", title: "Open…", hint: "⌘O", words: ["file", "document"], disabled: locked) { [unowned self] in openFile() },
            AppCommand(id: "new", title: "New document", hint: "⌘N", words: ["blank", "start"], disabled: locked) { [unowned self] in newDocument() },
            AppCommand(id: "build", title: "Build now", hint: "⌘R", words: ["set", "compile", "typeset", "rebuild"], disabled: busy) { [unowned self] in build() },
            AppCommand(id: "live", title: autoBuild ? "Stop building as I type" : "Build as I type", words: ["live", "auto", "rebuild", "debounce", "set"]) { [unowned self] in autoBuild.toggle() },
            AppCommand(id: "autosave", title: autoSave ? "Stop autosaving" : "Autosave every 10 seconds", words: ["autosave", "auto", "save", "write"]) { [unowned self] in autoSave.toggle() },
            AppCommand(id: "offline", title: offline ? "Allow the network" : "Refuse the network", words: ["offline", "online", "cache"]) { [unowned self] in toggleOffline() },
            AppCommand(id: "zoomin", title: "Zoom in on the preview", hint: "⌘+", words: ["enlarge", "bigger", "proof"]) { [unowned self] in zoom(by: 1) },
            AppCommand(id: "zoomout", title: "Zoom out of the preview", hint: "⌘−", words: ["reduce", "smaller", "proof"]) { [unowned self] in zoom(by: -1) },
            AppCommand(id: "zoomfit", title: "Fit the preview to width", hint: "⌘0", words: ["zoom", "fit", "width", "reset", "proof"]) { [unowned self] in zoom = .fit },
            AppCommand(id: "marks", title: "Show issues", words: ["errors", "warnings", "problems", "marks"], disabled: visible.isEmpty) { [unowned self] in rightPane = .marks },
            AppCommand(id: "presslog", title: pressOpen ? "Hide the press log" : "Show the press log", words: ["log", "tex", "passes"]) { [unowned self] in pressOpen.toggle() },
            AppCommand(id: "welcome", title: "Back to the title page", words: ["welcome", "home", "recent"]) { [unowned self] in screen = .welcome },
            AppCommand(id: "prime", title: "Download the LaTeX essentials", words: ["prime", "cache", "offline", "packages", "fonts", "setup"], disabled: cache == .downloading) { [unowned self] in setUp() },
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

struct PaletteView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var active = 0

    var body: some View {
        let rows = PaletteRow.rows(for: query, commands: model.commands, hasSelection: !model.selection.isEmpty)
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty

        GeometryReader { geo in
            ZStack(alignment: .top) {
                Tone.scrim
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)

                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Text("⌘K").font(Fonts.mono(13)).foregroundStyle(Tone.accent)
                        PaletteField(
                            text: $query,
                            onMove: { move($0, in: rows) },
                            onSubmit: { choose(rows.indices.contains(active) ? rows[active] : nil) },
                            onCancel: close
                        )
                        Text(searching ? "Plain English" : "Commands")
                            .rubric(Tone.text34, tracking: 0.14)
                            .fixedSize()
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 22)
                    .overlay(alignment: .bottom) { Hairline(color: Tone.rule14) }

                    ScrollViewReader { scroller in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                if rows.isEmpty {
                                    Text("Nothing matches. Try naming what you want — \u{201C}a bulleted list\u{201D}, \u{201C}aligned equations\u{201D}, \u{201C}a figure with a caption\u{201D}.")
                                        .font(Fonts.body(12.5, italic: true))
                                        .foregroundStyle(Tone.text38)
                                        .padding(.horizontal, 22)
                                        .padding(.top, 10)
                                        .padding(.bottom, 18)
                                }
                                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                                    if searching && i == 0 { group("Best match") }
                                    if searching && i == 1 {
                                        group("Also")
                                            .padding(.top, 8)
                                            .overlay(alignment: .top) { Hairline(color: Tone.ruleSoft) }
                                            .padding(.top, 10)
                                    }
                                    PaletteItem(row: row, active: i == active, best: i == 0 && searching)
                                        .id(i)
                                        .onTapGesture { choose(row) }
                                        .onContinuousHover { if case .active = $0 { active = i } }
                                }
                            }
                            .padding(.top, 14)
                            .padding(.bottom, 8)
                        }
                        .onChange(of: active) { _, i in scroller.scrollTo(i) }
                    }
                    .frame(maxHeight: max(120, geo.size.height - 148 - 64 - 40))
                    .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text("↑↓ to choose · ↵ to \(rows.first?.command != nil ? "run" : "insert")")
                        Spacer()
                    }
                    .font(Fonts.body(11))
                    .foregroundStyle(Tone.text38)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 22)
                    .background(Tone.inkEditor)
                    .overlay(alignment: .top) { Hairline(color: Tone.rule10) }
                }
                .frame(width: min(600, geo.size.width - 48))
                .background(Tone.inkPanel)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Tone.accentEdge, lineWidth: 1) }
                .shadow(color: .black.opacity(0.6), radius: 30, y: 24)
                .padding(.top, 74)
            }
        }
        .onChange(of: query) { active = 0 }
    }

    private func group(_ label: String) -> some View {
        Text(label)
            .rubric(Tone.text34, size: 10)
            .padding(.vertical, 8)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func move(_ by: Int, in rows: [PaletteRow]) {
        active = max(0, min(rows.count - 1, active + by))
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
    var row: PaletteRow
    var active: Bool
    var best: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(Fonts.body(best ? 15 : 14.5))
                    .foregroundStyle(best ? Tone.text : Tone.text82)
                if let preview = row.preview {
                    Text(preview)
                        .font(Fonts.mono(11.5))
                        .foregroundStyle(Tone.text45)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
            if best {
                Keycap(label: "↵", color: Tone.accent, edge: Tone.accent.opacity(0.5))
            } else if let hint = row.hint {
                Text(hint).font(Fonts.mono(11)).foregroundStyle(Tone.text.opacity(0.35))
            }
        }
        .padding(.vertical, best ? 12 : 11)
        .padding(.horizontal, 22)
        .background(active ? Tone.accentWash : .clear)
        .overlay(alignment: .leading) {
            Rectangle().fill(active ? Tone.accent : .clear).frame(width: 2)
        }
        .contentShape(Rectangle())
    }
}

/// The palette's text field. AppKit's, because the arrow keys, Return and
/// Escape have to reach the palette rather than the field editor.
private struct PaletteField: NSViewRepresentable {
    @Binding var text: String
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusingField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        _ = Fonts.registered
        field.font = NSFont(name: "Lora-Regular", size: 18) ?? .systemFont(ofSize: 18)
        field.textColor = Ink.text
        field.placeholderAttributedString = NSAttributedString(
            string: "put a 3 by 4 table here",
            attributes: [.foregroundColor: Ink.text(0.24), .font: field.font!]
        )
        field.delegate = context.coordinator
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteField

        init(_ parent: PaletteField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel()
            default: return false
            }
            return true
        }
    }

    final class FocusingField: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window else { return }
                window.makeFirstResponder(self)
                (currentEditor() as? NSTextView)?.insertionPointColor = Ink.accent
            }
        }
    }
}
