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
}

struct SourceEditor: NSViewRepresentable {
    var model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = LatexTextView.scrollableTextView()
        scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 34, left: 0, bottom: 40, right: 30)
        scroll.backgroundColor = Ink.editor
        scroll.drawsBackground = true

        let view = scroll.documentView as! LatexTextView
        view.configure()
        view.textDelegate = context.coordinator
        view.load(model.editor.pending ?? model.source)
        model.editor.pending = nil
        model.editor.view = view
        context.coordinator.view = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {}

    final class Coordinator: STTextViewDelegate {
        let model: AppModel
        weak var view: LatexTextView?
        /// The span the last edit touched, re-coloured once the change lands.
        private var edited: NSRange?

        init(model: AppModel) {
            self.model = model
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
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view else { return }
            let range = view.textSelection
            model.selection = range.length == 0 ? "" : ((view.text ?? "") as NSString).substring(with: range)
            view.matchBrackets()
        }

        func textView(_ textView: STTextView, completionItemsAtLocation location: any NSTextLocation) -> [any STCompletionItem]? {
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

    func configure() {
        font = Self.font
        textColor = Ink.text
        backgroundColor = Ink.editor
        insertionPointColor = Ink.accent
        isHorizontallyResizable = false  // wrap lines
        highlightSelectedLine = true
        selectedLineHighlightColor = Ink.accent(0.07)
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticTextCompletionEnabled = false

        // A 28px rhythm, so lines align with the page beside them.
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 28 / NSLayoutManager().defaultLineHeight(for: Self.font)
        defaultParagraphStyle = paragraph

        showsLineNumbers = true
        if let gutter = gutterView {
            gutter.drawSeparator = false
            gutter.textColor = Ink.text(0.24)
            gutter.selectedLineTextColor = Ink.text(0.55)
            gutter.selectedLineHighlightColor = .clear
            gutter.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
            gutter.insets = STRulerInsets(leading: 12, trailing: 14)
            gutter.minimumThickness = 48
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
    }

    func load(_ text: String) {
        isLoading = true
        self.text = text
        textSelection = NSRange(location: 0, length: 0)
        undoManager?.removeAllActions()
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
            addAttributes([.foregroundColor: Ink.text, .font: Self.font], range: range)
            latexTokens(in: text, range: range) { token, kind in
                switch kind {
                case .command:
                    addAttributes([.foregroundColor: Ink.accent], range: token)
                case .environment, .math:
                    addAttributes([.foregroundColor: Ink.accent400], range: token)
                case .bracket:
                    addAttributes([.foregroundColor: Ink.text(0.55)], range: token)
                case .comment:
                    addAttributes([.foregroundColor: Ink.text(0.38), .font: Self.italic], range: token)
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
            for range in matched { addRenderingAttributes([.backgroundColor: Ink.accent(0.18)], range: range) }
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
            .font(Fonts.mono(12.5))
            .foregroundStyle(Tone.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6))
    }
}
