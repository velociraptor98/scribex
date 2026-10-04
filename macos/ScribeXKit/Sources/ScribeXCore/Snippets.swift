/*
 * Snippet matching for the ⌘K palette: plain English in, LaTeX out.
 *
 * Matching is a local keyword score, so the vocabulary below does the work —
 * synonyms matter more here than clever ranking.
 */

import Foundation

/// Where the caret should land after an insertion. Stripped before insert.
public let caret = "\u{2038}"

public struct Suggestion: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// The LaTeX this will insert, elided for display.
    public var preview: String?
    /// A keyboard equivalent, when the action has one.
    public var hint: String?
    /// Empty for "turn the selection into a table", which the caller builds
    /// from the selection itself.
    public var text: String
    public var score: Double
}

private struct Query: Sendable {
    var words: [String]
    /// First two integers in the query, e.g. "3 by 4" → [3, 4].
    var nums: [Int]
    var hasSelection: Bool

    var cols: Int { clamp(nums.first ?? 3, 1, 12) }
    var rows: Int { clamp(nums.count > 1 ? nums[1] : nums.first ?? 3, 1, 40) }
}

private func clamp(_ n: Int, _ lo: Int, _ hi: Int) -> Int { min(hi, max(lo, n)) }

private struct Built: Sendable {
    var title: String
    var preview: String?
    var text: String
    var hint: String?
}

private struct Intent: Sendable {
    var id: String
    /// Words that should pull this intent up. Stemmed loosely by prefix match.
    var words: [String]
    /// Tie-break weight. Two intents often match a query equally well — "a table"
    /// hits both `table` and `booktabs` — and the plainer reading should win
    /// unless the query names the specialised one. Small enough that it never
    /// overturns a genuinely better keyword match.
    var bias: Double = 0
    /// Built from the query so counts and names can flow into the title.
    var build: @Sendable (Query) -> Built
}

private func tabular(_ c: Int, _ r: Int, booktabs: Bool) -> String {
    let spec = String(repeating: "l", count: c)
    func row(_ cell: String) -> String { (1...c).map { "\(cell)\($0)" }.joined(separator: " & ") }
    var body = ["  \(row("Head")) \\\\", booktabs ? "  \\midrule" : "  \\hline"]
    for _ in 0..<r { body.append("  \(row("Cell")) \\\\") }
    return (["\\begin{tabular}{\(spec)}", booktabs ? "  \\toprule" : "  \\hline"]
        + body
        + [booktabs ? "  \\bottomrule" : "  \\hline", "\\end{tabular}\(caret)"])
        .joined(separator: "\n")
}

private func s(_ n: Int) -> String { n > 1 ? "s" : "" }

private let intents: [Intent] = [
    Intent(id: "table", words: ["table", "tabular", "grid", "rows", "columns", "cells", "spreadsheet", "matrix of"], bias: 0.03) { q in
        let c = q.cols, r = q.rows
        return Built(
            title: "Insert a table — \(c) column\(s(c)) × \(r) row\(s(r))",
            preview: "\\begin{tabular}{\(String(repeating: "l", count: c))} … \\end{tabular}",
            text: tabular(c, r, booktabs: false)
        )
    },
    Intent(id: "booktabs", words: ["booktabs", "ruled", "professional", "toprule", "midrule", "table", "no verticals"]) { q in
        Built(
            title: "Insert a booktabs table (ruled, no verticals)",
            preview: "\\usepackage{booktabs} · \\toprule … \\bottomrule",
            text: tabular(q.cols, q.rows, booktabs: true)
        )
    },
    Intent(id: "caption", words: ["caption", "label", "title", "number", "reference", "cross"]) { _ in
        Built(title: "Add a caption and a label", preview: "\\caption{…} \\label{tab:…}", text: "\\caption{\(caret)}\n\\label{tab:key}")
    },
    Intent(id: "twocolumn", words: ["two", "column", "columns", "twocolumn", "double", "page", "layout"]) { _ in
        Built(title: "Set the page in two columns", preview: "\\documentclass[twocolumn]{…} · \\twocolumn", text: "\\twocolumn\(caret)")
    },
    Intent(id: "equation", words: ["equation", "maths", "math", "formula", "numbered", "display", "expression"]) { _ in
        Built(title: "Insert a numbered equation", preview: "\\begin{equation} … \\end{equation}", text: "\\begin{equation}\n  \(caret)\n\\end{equation}")
    },
    Intent(id: "align", words: ["align", "aligned", "multiline", "several", "lines", "equations", "system"]) { _ in
        Built(title: "Insert aligned equations", preview: "\\begin{align} … \\end{align}", text: "\\begin{align}\n  \(caret) &= \\\\\n   &=\n\\end{align}")
    },
    Intent(id: "figure", words: ["figure", "image", "picture", "graphic", "photo", "diagram", "includegraphics", "plot"]) { _ in
        Built(
            title: "Insert a figure with a caption",
            preview: "\\begin{figure} \\includegraphics … \\end{figure}",
            text: [
                "\\begin{figure}[htbp]",
                "  \\centering",
                "  \\includegraphics[width=0.8\\textwidth]{\(caret)}",
                "  \\caption{}",
                "  \\label{fig:key}",
                "\\end{figure}",
            ].joined(separator: "\n")
        )
    },
    Intent(id: "itemize", words: ["bullet", "bullets", "list", "itemize", "unordered", "points", "dot"]) { _ in
        Built(title: "Insert a bulleted list", preview: "\\begin{itemize} \\item … \\end{itemize}", text: "\\begin{itemize}\n  \\item \(caret)\n  \\item\n\\end{itemize}")
    },
    Intent(id: "enumerate", words: ["numbered", "list", "enumerate", "ordered", "steps", "count"]) { _ in
        Built(title: "Insert a numbered list", preview: "\\begin{enumerate} \\item … \\end{enumerate}", text: "\\begin{enumerate}\n  \\item \(caret)\n  \\item\n\\end{enumerate}")
    },
    Intent(id: "section", words: ["section", "heading", "header", "chapter", "part", "title"]) { _ in
        Built(title: "Start a new section", preview: "\\section{…}", text: "\\section{\(caret)}")
    },
    Intent(id: "cite", words: ["cite", "citation", "reference", "bibliography", "source", "paper", "bibtex"]) { _ in
        Built(title: "Cite a work", preview: "\\cite{key}", text: "\\cite{\(caret)}")
    },
    Intent(id: "ref", words: ["ref", "reference", "refer", "cross", "link", "point", "equation", "figure"]) { _ in
        Built(title: "Refer to a label", preview: "\\ref{key}", text: "\\ref{\(caret)}")
    },
    Intent(id: "footnote", words: ["footnote", "note", "aside", "remark", "bottom"]) { _ in
        Built(title: "Add a footnote", preview: "\\footnote{…}", text: "\\footnote{\(caret)}")
    },
    Intent(id: "matrix", words: ["matrix", "matrices", "array", "bracket", "pmatrix", "determinant"]) { q in
        let c = q.cols, r = q.rows
        let body = (0..<r).map { _ in Array(repeating: "0", count: c).joined(separator: " & ") }
            .joined(separator: " \\\\\n  ")
        return Built(
            title: "Insert a \(c) × \(r) matrix",
            preview: "\\begin{pmatrix} … \\end{pmatrix}",
            text: "\\begin{pmatrix}\n  \(body)\n\\end{pmatrix}\(caret)"
        )
    },
    Intent(id: "verbatim", words: ["code", "verbatim", "listing", "monospace", "program", "snippet"]) { _ in
        Built(title: "Insert a code block", preview: "\\begin{verbatim} … \\end{verbatim}", text: "\\begin{verbatim}\n\(caret)\n\\end{verbatim}")
    },
    Intent(id: "quote", words: ["quote", "quotation", "block", "excerpt", "indent"]) { _ in
        Built(title: "Insert a block quotation", preview: "\\begin{quote} … \\end{quote}", text: "\\begin{quote}\n  \(caret)\n\\end{quote}")
    },
    Intent(id: "bold", words: ["bold", "strong", "heavy", "textbf", "emphasis"]) { q in
        Built(
            title: q.hasSelection ? "Set the selection in bold" : "Set text in bold",
            preview: "\\textbf{…}", text: "\\textbf{\(caret)}", hint: "⌘B"
        )
    },
    Intent(id: "italic", words: ["italic", "italics", "emphasise", "emphasize", "emph", "slanted"]) { q in
        Built(
            title: q.hasSelection ? "Set the selection in italics" : "Set text in italics",
            preview: "\\emph{…}", text: "\\emph{\(caret)}", hint: "⌘I"
        )
    },
    Intent(id: "toc", words: ["contents", "toc", "tableofcontents", "outline", "index"]) { _ in
        Built(title: "Insert a table of contents", preview: "\\tableofcontents", text: "\\tableofcontents\(caret)")
    },
    Intent(id: "abstract", words: ["abstract", "summary", "synopsis"]) { _ in
        Built(title: "Insert an abstract", preview: "\\begin{abstract} … \\end{abstract}", text: "\\begin{abstract}\n  \(caret)\n\\end{abstract}")
    },
    Intent(id: "package", words: ["package", "usepackage", "import", "library", "load"]) { _ in
        Built(title: "Load a package", preview: "\\usepackage{…}", text: "\\usepackage{\(caret)}")
    },
    Intent(id: "pagebreak", words: ["page", "break", "newpage", "clearpage", "next"]) { _ in
        Built(title: "Break to a new page", preview: "\\newpage", text: "\\newpage\(caret)")
    },
]

/// Selection-aware variants, offered only when there is something selected.
private let wrappers: [Intent] = [
    Intent(id: "wrap-table", words: ["table", "turn", "convert", "selection", "into", "make"]) { _ in
        Built(title: "Turn the selection into a table", preview: "rows of tab- or comma-separated text → tabular", text: "")
    },
]

// Filler that would otherwise match everything.
private let stopWords: Set<String> = [
    "the", "and", "for", "with", "put", "add", "insert", "make", "give", "get",
    "here", "there", "this", "that", "please", "can", "you", "would", "like",
    "want", "need", "some", "into", "onto", "new", "one",
]

public func tokenize(_ s: String) -> [String] {
    s.lowercased()
        .split(whereSeparator: { !($0.isASCII && ($0.isLetter || $0.isNumber)) })
        .map(String.init)
        .filter { $0.count > 1 && !stopWords.contains($0) }
}

private func score(_ intent: Intent, _ words: [String]) -> Double {
    if words.isEmpty { return 0 }
    var hits = 0
    for w in words {
        for k in intent.words {
            if k == w {
                hits += 2
                break
            }
            if k.hasPrefix(w) || w.hasPrefix(k) {
                hits += 1
                break
            }
        }
    }
    // Normalise so a long intent vocabulary is not an advantage.
    return hits == 0 ? 0 : Double(hits) / Double(words.count)
}

/// Rank snippet intents against a plain-English query.
public func suggest(_ text: String, hasSelection: Bool = false, limit: Int = 6) -> [Suggestion] {
    let words = tokenize(text)
    let q = Query(
        words: words,
        nums: text.matches(of: #/\d+/#).prefix(2).compactMap { Int($0.output) },
        hasSelection: hasSelection
    )

    let pool = hasSelection ? intents + wrappers : intents
    var out: [Suggestion] = []
    for intent in pool {
        let sc = score(intent, words)
        if sc <= 0 { continue }
        let built = intent.build(q)
        out.append(Suggestion(
            id: intent.id, title: built.title, preview: built.preview, hint: built.hint,
            text: built.text, score: sc + intent.bias
        ))
    }

    out.sort { a, b in
        a.score != b.score ? a.score > b.score : a.title.localizedCompare(b.title) == .orderedAscending
    }
    return Array(out.prefix(limit))
}

/// Convert tab- or comma-separated lines into a tabular environment.
public func selectionToTable(_ selection: String) -> String? {
    let lines = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    if lines.isEmpty { return nil }
    let grid = lines.map { line in
        line.components(separatedBy: line.contains("\t") ? "\t" : ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    let width = grid.map(\.count).max() ?? 0
    if width < 2 { return nil }
    let body = grid
        .map { "  " + ($0 + Array(repeating: "", count: width - $0.count)).joined(separator: " & ") + " \\\\" }
        .joined(separator: "\n")
    return "\\begin{tabular}{\(String(repeating: "l", count: width))}\n  \\hline\n\(body)\n  \\hline\n\\end{tabular}"
}
