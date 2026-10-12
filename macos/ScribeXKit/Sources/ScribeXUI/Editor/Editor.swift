import AppKit
import ScribeXCore
import STTextView
import SwiftUI

public final class EditorHandle {
    fileprivate weak var view: LatexTextView?
    /// Text loaded before the view exists.
    fileprivate var pending: String?

    /// Clears undo history too, so you cannot undo your way out of a newly
    /// opened file and back into the previous one.
    func load(_ text: String) {
        guard let view else {
            pending = text
            return
        }
        view.load(text)
    }

    /// A `caret` marker in `text` sets where the caret lands; otherwise it lands
    /// after the insertion.
    func insert(_ text: String) {
        guard let view else { return }
        let marker = (text as NSString).range(of: caret)
        let clean = text.replacingOccurrences(of: caret, with: "")
        let at = view.textSelection
        view.replaceCharacters(in: at, with: clean)
        let landing = marker.location == NSNotFound ? (clean as NSString).length : marker.location
        view.textSelection = NSRange(location: at.location + landing, length: 0)
        view.scrollRangeToVisible(view.textSelection)
        focus()
    }

    /// `line` is 1-based.
    func replaceOnLine(_ line: Int, find: String, replace: String) {
        guard let view, let range = view.range(ofLine: line) else { return }
        let text = (view.text ?? "") as NSString
        let hit = text.range(of: find, range: range)
        guard hit.location != NSNotFound else { return }
        view.replaceCharacters(in: hit, with: replace)
        view.textSelection = NSRange(location: hit.location + (replace as NSString).length, length: 0)
        view.scrollRangeToVisible(view.textSelection)
    }

    func goto(_ line: Int) {
        guard let view, let range = view.range(ofLine: line) else { return }
        view.textSelection = NSRange(location: range.location, length: 0)
        view.scrollRangeToVisible(view.textSelection)
        focus()
    }

    func focus() {
        guard let view else { return }
        view.window?.makeFirstResponder(view)
    }

    /// Read when needed rather than mirrored on every selection change.
    var selectedText: String {
        guard let view, view.textSelection.length > 0 else { return "" }
        return ((view.text ?? "") as NSString).substring(with: view.textSelection)
    }
}

struct Editor: NSViewRepresentable {
    var model: Session
    /// The cursor's line, 1-based, for the sidebar to show where you are.
    @Binding var caretLine: Int
    /// Room around the text: above the first line, so it lines up with the
    /// first row of the panes beside it, and clear of the bottom and right.
    private static let insets = NSEdgeInsets(top: 34, left: 0, bottom: 40, right: 30)

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = LatexTextView.scrollableTextView()
        scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = Self.insets
        // The scroller sits inside the content insets, which are only there to
        // pad the text; undone, it runs the full height at the window's edge.
        let i = Self.insets
        scroll.scrollerInsets = NSEdgeInsets(top: -i.top, left: -i.left, bottom: -i.bottom, right: -i.right)
        scroll.backgroundColor = NSColor.scribeEditor
        scroll.drawsBackground = true

        let view = scroll.documentView as! LatexTextView
        view.configure()
        // Edits go on the document's undo manager: that is what marks the
        // window edited and lets autosave and Edit ▸ Undo work.
        context.coordinator.undoManager = context.environment.undoManager
        view.textDelegate = context.coordinator
        view.load(model.editor.pending ?? model.source)
        model.editor.pending = nil
        model.editor.view = view
        context.coordinator.view = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.undoManager = context.environment.undoManager
        context.coordinator.caretLine = $caretLine
        let view = scroll.documentView as! LatexTextView
        view.markIssues(model.typesetting.visible)
        if let note = model.typesetting.missingFile {
            let host = context.coordinator.noteHost ?? NoteHost(rootView: LineNote(note: note, session: model))
            host.rootView = LineNote(note: note, session: model)
            context.coordinator.noteHost = host
            view.pin(host, line: note.line)
        } else {
            view.pin(nil, line: 0)
        }
    }

    final class Coordinator: STTextViewDelegate {
        let model: Session
        weak var view: LatexTextView?
        weak var undoManager: UndoManager?
        var caretLine: Binding<Int>?
        var noteHost: NoteHost?
        /// The span the last edit touched, re-coloured once the change lands.
        private var edited: NSRange?

        init(model: Session) {
            self.model = model
        }

        /// The document's undo manager, from SwiftUI's environment. Edits
        /// registered there are what the document system counts as changes,
        /// so autosave, the edited state and ⌘Z all follow the editor.
        func undoManager(for textView: STTextView) -> UndoManager? {
            undoManager
        }

        func textView(_ textView: STTextView, shouldChangeTextIn affectedCharRange: NSTextRange, replacementString: String?) -> Bool {
            guard let view, let replacementString else { return true }
            return view.shouldType(replacementString, in: NSRange(affectedCharRange, in: textView.textContentManager))
        }

        func textView(_ textView: STTextView, didChangeTextIn affectedCharRange: NSTextRange, replacementString: String) {
            let start = textView.textContentManager.offset(from: textView.textContentManager.documentRange.location, to: affectedCharRange.location)
            edited = NSRange(location: start, length: (replacementString as NSString).length)
        }

        func textViewDidChangeText(_ notification: Notification) {
            guard let view else { return }
            if let edited { view.highlight(around: edited) }
            edited = nil
            if !view.isLoading {
                model.edit(view.text ?? "")
                view.completeIfTyping()
            }
            view.placePinned()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view else { return }
            view.matchBrackets()
            let before = ((view.text ?? "") as NSString).substring(to: view.textSelection.location)
            let line = before.utf16.reduce(1) { $1 == 10 ? $0 + 1 : $0 }
            if caretLine?.wrappedValue != line { caretLine?.wrappedValue = line }
        }

        func textView(_ textView: STTextView, completionItemsAtLocation location: any NSTextLocation) -> [any STCompletionItem]? {
            view?.completions()
        }

        /// STTextView asks for completions from a background task. Without
        /// this async version the synchronous one above stands in for it and
        /// runs off the main actor, which traps; being main-actor isolated,
        /// this one is called with a hop back to the main thread.
        func textView(_ textView: STTextView, completionItemsAtLocation location: any NSTextLocation) async -> [any STCompletionItem]? {
            view?.completions()
        }

        func textView(_ textView: STTextView, insertCompletionItem item: any STCompletionItem) {
            guard let item = item as? LatexCompletion else { return }
            view?.accept(item)
        }
    }
}

final class LatexTextView: STTextView {
    /// A document being swapped in, which is not an edit.
    private(set) var isLoading = false
    /// The view's own edit in response to typing, which must not be intercepted.
    private var autoEditing = false
    private var matched: [NSRange] = []

    private static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let italic = NSFont(
        descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: 13
    ) ?? font
    private static let indent = "  "
    /// Lines 28pt apart, so they align with the page beside them, with the text
    /// centred in each. TextKit counts a baseline offset into the line height:
    /// lifting the text 9pt to the middle (it sits at the bottom of a taller
    /// line) shrinks the line by 3pt, so it is set 3pt taller. Both measured.
    /// A height multiple would be simpler, but STTextView's centring of those
    /// overshoots and leaves the text about 4pt high.
    private static let lineHeight: CGFloat = 31
    private static let lift: CGFloat = 9

    func configure() {
        font = Self.font
        textColor = NSColor.scribeInk
        backgroundColor = NSColor.scribeEditor
        insertionPointColor = NSColor.scribeGilt
        isHorizontallyResizable = false  // wrap lines
        highlightSelectedLine = true
        selectedLineHighlightColor = NSColor.scribeGilt.withAlphaComponent(0.07)
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticTextCompletionEnabled = false

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Self.lineHeight
        paragraph.maximumLineHeight = Self.lineHeight
        defaultParagraphStyle = paragraph

        showsLineNumbers = true
        if let gutter = gutterView {
            gutter.drawSeparator = false
            gutter.textColor = NSColor.scribeInk.withAlphaComponent(0.24)
            gutter.selectedLineTextColor = NSColor.scribeInk.withAlphaComponent(0.55)
            gutter.selectedLineHighlightColor = .clear
            gutter.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
            // Room on the left for the issue markers.
            gutter.insets = STRulerInsets(leading: 22, trailing: 14)
            gutter.minimumThickness = 58
        }
    }

    /// The gutter floats over the scroll view and does not know about its top
    /// inset (STTextView corrects for that only with automatic insets), so it
    /// would sit one inset below the lines it numbers.
    override func layout() {
        super.layout()
        if let gutter = gutterView, let inset = enclosingScrollView?.contentInsets.top,
           gutter.frame.origin.y != -inset {
            gutter.frame.origin.y = -inset
        }
        placePinned()
    }

    private var pinned: (view: NSView, line: Int)?
    private var marked: [Int: Diagnostic.Severity] = [:]

    /// An icon in the gutter on each line with an issue, as Xcode marks them. An error outranks a warning on the same line.
    func markIssues(_ issues: [Diagnostic]) {
        var lines: [Int: Diagnostic.Severity] = [:]
        for issue in issues {
            guard let line = issue.line else { continue }
            if lines[line] != .error { lines[line] = issue.severity }
        }
        guard lines != marked, let gutter = gutterView else { return }
        for line in marked.keys { gutter.removeMarker(lineNumber: line) }
        for (line, severity) in lines {
            gutter.addMarker(STGutterMarker(lineNumber: line, view: IssueMarker(severity: severity)))
        }
        marked = lines
        gutter.needsLayout = true
    }

    /// Keeps `view` at the end of `line` (1-based), or removes the one there.
    func pin(_ view: NSView?, line: Int) {
        if pinned?.view !== view { pinned?.view.removeFromSuperview() }
        guard let view else {
            pinned = nil
            return
        }
        if view.superview !== self { addSubview(view) }
        pinned = (view, line)
        placePinned()
    }

    /// Against the right edge of what's visible, centred on the line, as Xcode
    /// sets its issues. Lines move with every edit, so this runs after each one.
    func placePinned() {
        guard let (view, line) = pinned else { return }
        guard let range = range(ofLine: line), let window else {
            view.isHidden = true
            return
        }
        let end = NSRange(location: NSMaxRange(range), length: 0)
        let caret = convert(window.convertFromScreen(firstRect(forCharacterRange: end, actualRange: nil)), from: nil)
        let right = enclosingScrollView?.documentVisibleRect.maxX ?? bounds.maxX
        // Narrowed to its icon and button when the whole note would cover the text.
        (view as? NoteHost)?.fit(in: right - 12 - (caret.maxX + 16))
        let size = view.fittingSize
        view.frame = NSRect(
            x: right - size.width - 12,
            y: caret.midY - size.height / 2,
            width: size.width, height: size.height
        )
        view.isHidden = false
        window.invalidateCursorRects(for: view)
    }

    /// Opening a file is not an edit: nothing to undo, and the document stays clean.
    func load(_ text: String) {
        isLoading = true
        undoManager?.disableUndoRegistration()
        self.text = text
        undoManager?.enableUndoRegistration()
        textSelection = NSRange(location: 0, length: 0)
        highlightAll()
        isLoading = false
    }

    /// `line` is 1-based; the range excludes the line break.
    func range(ofLine line: Int) -> NSRange? {
        guard line >= 1 else { return nil }
        let text = (self.text ?? "") as NSString
        var start = 0
        for _ in 1..<line {
            let next = text.range(of: "\n", range: NSRange(location: start, length: text.length - start))
            if next.location == NSNotFound { return nil }
            start = next.location + 1
        }
        let end = text.range(of: "\n", range: NSRange(location: start, length: text.length - start))
        return NSRange(location: start, length: (end.location == NSNotFound ? text.length : end.location) - start)
    }

    private func highlightAll() {
        let length = ((text ?? "") as NSString).length
        highlight(NSRange(location: 0, length: length))
    }

    /// Re-colour the whole lines around an edit. Every token ends at a line
    /// break, so nothing outside them can have changed.
    func highlight(around edit: NSRange) {
        let text = (self.text ?? "") as NSString
        let clamped = NSIntersectionRange(edit, NSRange(location: 0, length: text.length))
        let lines = text.lineRange(for: NSRange(location: min(edit.location, text.length), length: clamped.length))
        highlight(lines)
    }

    private func highlight(_ range: NSRange) {
        guard range.length > 0 else { return }
        let text = (self.text ?? "") as NSString
        // One transaction for the lot, rather than a layout pass per token.
        textContentManager.performEditingTransaction {
            addAttributes([.foregroundColor: NSColor.scribeInk, .font: Self.font, .baselineOffset: Self.lift], range: range)
            latexTokens(in: text, range: range) { token, kind in
                switch kind {
                case .command:
                    addAttributes([.foregroundColor: NSColor.scribeGilt], range: token)
                case .environment, .math:
                    addAttributes([.foregroundColor: NSColor.scribeGiltLight], range: token)
                case .bracket:
                    addAttributes([.foregroundColor: NSColor.scribeInk.withAlphaComponent(0.55)], range: token)
                case .comment:
                    addAttributes([.foregroundColor: NSColor.scribeInk.withAlphaComponent(0.4), .font: Self.italic], range: token)
                }
            }
        }
    }

    private static let pairs: [String: String] = ["{": "}", "[": "]", "(": ")"]

    /// Returns false when it has made the edit itself: closing a bracket as it
    /// opens, or stepping over a closing bracket already there.
    func shouldType(_ string: String, in range: NSRange) -> Bool {
        guard !autoEditing, !isLoading else { return true }
        let text = (self.text ?? "") as NSString
        let next = range.location + range.length < text.length
            ? text.substring(with: NSRange(location: range.location + range.length, length: 1)) : ""

        if let close = Self.pairs[string] {
            autoEditing = true
            defer { autoEditing = false }
            let selected = text.substring(with: range)
            replaceCharacters(in: range, with: string + selected + close)
            textSelection = NSRange(location: range.location + 1, length: (selected as NSString).length)
            return false
        }
        if range.length == 0, Self.pairs.values.contains(string), next == string {
            textSelection = NSRange(location: range.location + 1, length: 0)
            return false
        }
        return true
    }

    func matchBrackets() {
        for range in matched { removeRenderingAttribute(.backgroundColor, range: range) }
        matched = []
        let selection = textSelection
        guard selection.length == 0 else { return }
        let text = (self.text ?? "") as NSString
        let candidates = [selection.location - 1, selection.location].filter { $0 >= 0 && $0 < text.length }
        for at in candidates {
            guard let partner = partner(of: at, in: text) else { continue }
            matched = [NSRange(location: at, length: 1), NSRange(location: partner, length: 1)]
            for range in matched { addRenderingAttributes([.backgroundColor: NSColor.scribeGilt.withAlphaComponent(0.18)], range: range) }
            return
        }
    }

    private func partner(of at: Int, in text: NSString) -> Int? {
        let opens: [unichar] = [123, 91, 40], closes: [unichar] = [125, 93, 41]
        let c = text.character(at: at)
        let forward: Bool
        let open: unichar, close: unichar
        if let i = opens.firstIndex(of: c) {
            (forward, open, close) = (true, c, closes[i])
        } else if let i = closes.firstIndex(of: c) {
            (forward, open, close) = (false, opens[i], c)
        } else {
            return nil
        }
        // An escaped brace (\{) is text, not structure.
        if at > 0, text.character(at: at - 1) == 92 { return nil }
        var depth = 0
        var i = at
        let limit = 20_000
        for _ in 0..<limit {
            let ch = text.character(at: i)
            let escaped = i > 0 && text.character(at: i - 1) == 92
            if !escaped {
                if ch == open { depth += forward ? 1 : -1 }
                if ch == close { depth += forward ? -1 : 1 }
                if depth == 0 { return i }
            }
            i += forward ? 1 : -1
            if i < 0 || i >= text.length { return nil }
        }
        return nil
    }

    /// Tab indents the selected lines rather than inserting a tab.
    override func insertTab(_ sender: Any?) {
        shiftLines(by: 1)
    }

    override func insertBacktab(_ sender: Any?) {
        shiftLines(by: -1)
    }

    private func shiftLines(by direction: Int) {
        let text = (self.text ?? "") as NSString
        let selection = textSelection
        let lines = text.lineRange(for: selection)
        // The range takes in the last line's break; leave that where it is.
        var body = text.substring(with: lines)
        let newline = body.hasSuffix("\n")
        if newline { body.removeLast() }

        var shifts: [Int] = []
        let rows = body.components(separatedBy: "\n").map { row in
            if direction > 0 {
                shifts.append(Self.indent.count)
                return Self.indent + row
            }
            let strip = row.prefix(Self.indent.count).prefix { $0 == " " }.count
            shifts.append(-strip)
            return String(row.dropFirst(strip))
        }

        autoEditing = true
        replaceCharacters(in: lines, with: rows.joined(separator: "\n") + (newline ? "\n" : ""))
        autoEditing = false
        let first = shifts[0], total = shifts.reduce(0, +)
        textSelection = NSRange(
            location: max(lines.location, selection.location + first),
            length: max(0, selection.length + total - first)
        )
    }

    /// Carries the current line's indentation onto the new one.
    override func insertNewline(_ sender: Any?) {
        let text = (self.text ?? "") as NSString
        let line = text.substring(with: text.lineRange(for: NSRange(location: textSelection.location, length: 0)))
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        breakUndoCoalescing()
        insertText("\n" + indent)
        breakUndoCoalescing()
    }

    private func typing() -> (from: Int, prefix: String, options: [String])? {
        let selection = textSelection
        guard selection.length == 0 else { return nil }
        let text = (self.text ?? "") as NSString
        let lineStart = text.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let before = text.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))

        if let m = before.firstMatch(of: #/\\(?:begin|end)\{([\w*]*)$/#) {
            let prefix = String(m.1)
            return (selection.location - (prefix as NSString).length, prefix, latexEnvironments)
        }
        if let m = before.firstMatch(of: #/\\([a-zA-Z]+)$/#) {
            let prefix = String(m.1)
            return (selection.location - (prefix as NSString).length, prefix, latexCommands)
        }
        return nil
    }

    func completions() -> [any STCompletionItem] {
        guard let typing = typing() else { return [] }
        return typing.options
            .filter { $0.hasPrefix(typing.prefix) && $0 != typing.prefix }
            .map { LatexCompletion(label: $0, from: typing.from) }
    }

    func completeIfTyping() {
        if typing() != nil {
            complete(nil)
        } else if isCompletionActive {
            cancelComplete(nil)
        }
    }

    func accept(_ item: LatexCompletion) {
        let end = textSelection.location
        guard end >= item.from else { return }
        replaceCharacters(in: NSRange(location: item.from, length: end - item.from), with: item.label)
        textSelection = NSRange(location: item.from + (item.label as NSString).length, length: 0)
    }
}

struct LatexCompletion: STCompletionItem {
    let label: String
    /// Where the text being completed starts.
    let from: Int

    var id: String { label }

    var view: NSView {
        NSHostingView(rootView: Text(label)
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6))
    }
}

/// A gutter marker: the issue's icon, left of the line number. (STTextView
/// draws numbers over its markers, so the icon can't stand in for one.)
private final class IssueMarker: NSView {
    let severity: Diagnostic.Severity

    init(severity: Diagnostic.Severity) {
        self.severity = severity
        super.init(frame: .zero)
        toolTip = severity == .error ? "Error on this line" : "Warning on this line"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let error = severity == .error
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            // The mark in the editor's colour, so it shows through the shape.
            .applying(.init(paletteColors: [.scribeEditor, error ? .scribeMark : .scribeGilt]))
        guard let icon = NSImage(systemSymbolName: error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill",
                                 accessibilityDescription: error ? "Error" : "Warning")?
            .withSymbolConfiguration(config) else { return }
        let size = icon.size
        icon.draw(in: NSRect(x: bounds.minX + 6, y: bounds.midY - size.height / 2,
                             width: size.width, height: size.height))
    }
}

/// Hosts the note inside the text view. The text view claims its whole area
/// for the I-beam; this claims the note's own area back for the arrow, so its
/// button reads as a button.
final class NoteHost: NSHostingView<LineNote> {
    /// Compact when the full note is wider than `width`.
    func fit(in width: CGFloat) {
        var full = rootView
        full.compact = false
        let compact = NSHostingView(rootView: full).fittingSize.width > width
        if rootView.compact != compact { rootView.compact = compact }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

/// Pinned to the line that asked for a file the build lacked.
struct LineNote: View {
    let note: Typesetting.MissingFile
    let session: Session
    /// Icon and button only, the message moving to the tooltip, where the
    /// line's text leaves no room for it.
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: note.fetchable ? "arrow.down.circle" : "questionmark.folder")
                .foregroundStyle(.gilt)
            if !compact {
                Text(message)
            }
            Group {
                if note.fetchable {
                    Button(session.typesetting.fetching ? "Fetching…" : "Fetch") { session.typesetting.build(allowNetwork: true) }
                        .disabled(session.typesetting.fetching)
                } else if session.fileURL != nil {
                    Button("Show Folder", action: session.revealFolder)
                }
            }
            .pointerStyle(.link)
        }
        .font(Fonts.text(12))
        .controlSize(.small)
        .buttonBorderShape(.capsule)
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        // Solid, so where a narrow editor leaves no room it covers the text
        // cleanly rather than mixing with it.
        .background(Color.gilt.opacity(0.14), in: .capsule)
        .background(Color(nsColor: .scribeEditor), in: .capsule)
        .help((compact ? "\(note.file) \(note.fetchable ? "isn’t downloaded" : "isn’t in this folder"). " : "")
            + (note.fetchable
                ? "Not in the download cache. Fetch downloads it once; it then stays available offline."
                : "Not part of the TeX distribution: put it in the same folder as the document."))
    }

    private var message: AttributedString {
        var file = AttributedString(note.file)
        file.font = .system(size: 12, design: .monospaced)
        return file + AttributedString(note.fetchable ? " isn’t downloaded" : " isn’t in this folder")
    }
}

#Preview {
    // The article template, coloured; typing and completion work in the canvas.
    Editor(model: .preview(), caretLine: .constant(1)).scribeStyle().frame(width: 640, height: 600)
}
