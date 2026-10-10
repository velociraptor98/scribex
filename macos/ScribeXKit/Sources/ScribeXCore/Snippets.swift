// Matching is plain text search over each intent's keywords, so the vocabulary
// below does the work: synonyms matter more here than clever ranking.

import Foundation

/// Where the caret should land after an insertion. Stripped before insert.
public let caret = "\u{2038}"

public struct Suggestion: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var preview: String?
    public var hint: String?
    /// Empty for "turn the selection into a table", which the caller builds
    /// from the selection itself.
    public var text: String
    public var score: Double

    /// What an intent builds; `suggest` fills in the id and the score.
    init(title: String, preview: String? = nil, text: String, hint: String? = nil) {
        id = ""
        self.title = title
        self.preview = preview
        self.hint = hint
        self.text = text
        score = 0
    }
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

private struct Intent: Sendable {
    var id: String
    /// Matched loosely, by prefix in either direction.
    var words: [String]
    /// Breaks ties toward the plainer reading: "a table" matches both `table`
    /// and `booktabs` equally. Too small to overturn a better keyword match.
    var bias: Double = 0
    var build: @Sendable (Query) -> Suggestion
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
        return Suggestion(
            title: "Insert a table — \(c) column\(s(c)) × \(r) row\(s(r))",
            preview: "\\begin{tabular}{\(String(repeating: "l", count: c))} … \\end{tabular}",
            text: tabular(c, r, booktabs: false)
        )
    },
    Intent(id: "booktabs", words: ["booktabs", "ruled", "professional", "toprule", "midrule", "table", "no verticals"]) { q in
        Suggestion(
            title: "Insert a booktabs table (ruled, no verticals)",
            preview: "\\usepackage{booktabs} · \\toprule … \\bottomrule",
            text: tabular(q.cols, q.rows, booktabs: true)
        )
    },
    Intent(id: "caption", words: ["caption", "label", "title", "number", "reference", "cross"]) { _ in
        Suggestion(title: "Add a caption and a label", preview: "\\caption{…} \\label{tab:…}", text: "\\caption{\(caret)}\n\\label{tab:key}")
    },
    Intent(id: "twocolumn", words: ["two", "column", "columns", "twocolumn", "double", "page", "layout"]) { _ in
        Suggestion(title: "Set the page in two columns", preview: "\\documentclass[twocolumn]{…} · \\twocolumn", text: "\\twocolumn\(caret)")
    },
    Intent(id: "equation", words: ["equation", "maths", "math", "formula", "numbered", "display", "expression"]) { _ in
        Suggestion(title: "Insert a numbered equation", preview: "\\begin{equation} … \\end{equation}", text: "\\begin{equation}\n  \(caret)\n\\end{equation}")
    },
    Intent(id: "align", words: ["align", "aligned", "multiline", "several", "lines", "equations", "system"]) { _ in
        Suggestion(title: "Insert aligned equations", preview: "\\begin{align} … \\end{align}", text: "\\begin{align}\n  \(caret) &= \\\\\n   &=\n\\end{align}")
    },
    Intent(id: "figure", words: ["figure", "image", "picture", "graphic", "photo", "diagram", "includegraphics", "plot"]) { _ in
        Suggestion(
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
        Suggestion(title: "Insert a bulleted list", preview: "\\begin{itemize} \\item … \\end{itemize}", text: "\\begin{itemize}\n  \\item \(caret)\n  \\item\n\\end{itemize}")
    },
    Intent(id: "enumerate", words: ["numbered", "list", "enumerate", "ordered", "steps", "count"]) { _ in
        Suggestion(title: "Insert a numbered list", preview: "\\begin{enumerate} \\item … \\end{enumerate}", text: "\\begin{enumerate}\n  \\item \(caret)\n  \\item\n\\end{enumerate}")
    },
    Intent(id: "section", words: ["section", "heading", "header", "chapter", "part", "title"]) { _ in
        Suggestion(title: "Start a new section", preview: "\\section{…}", text: "\\section{\(caret)}")
    },
    Intent(id: "cite", words: ["cite", "citation", "reference", "bibliography", "source", "paper", "bibtex"]) { _ in
        Suggestion(title: "Cite a work", preview: "\\cite{key}", text: "\\cite{\(caret)}")
    },
    Intent(id: "ref", words: ["ref", "reference", "refer", "cross", "link", "point", "equation", "figure"]) { _ in
        Suggestion(title: "Refer to a label", preview: "\\ref{key}", text: "\\ref{\(caret)}")
    },
    Intent(id: "footnote", words: ["footnote", "note", "aside", "remark", "bottom"]) { _ in
        Suggestion(title: "Add a footnote", preview: "\\footnote{…}", text: "\\footnote{\(caret)}")
    },
    Intent(id: "matrix", words: ["matrix", "matrices", "array", "bracket", "pmatrix", "determinant"]) { q in
        let c = q.cols, r = q.rows
        let body = (0..<r).map { _ in Array(repeating: "0", count: c).joined(separator: " & ") }
            .joined(separator: " \\\\\n  ")
        return Suggestion(
            title: "Insert a \(c) × \(r) matrix",
            preview: "\\begin{pmatrix} … \\end{pmatrix}",
            text: "\\begin{pmatrix}\n  \(body)\n\\end{pmatrix}\(caret)"
        )
    },
    Intent(id: "verbatim", words: ["code", "verbatim", "listing", "monospace", "program", "snippet"]) { _ in
        Suggestion(title: "Insert a code block", preview: "\\begin{verbatim} … \\end{verbatim}", text: "\\begin{verbatim}\n\(caret)\n\\end{verbatim}")
    },
    Intent(id: "quote", words: ["quote", "quotation", "block", "excerpt", "indent"]) { _ in
        Suggestion(title: "Insert a block quotation", preview: "\\begin{quote} … \\end{quote}", text: "\\begin{quote}\n  \(caret)\n\\end{quote}")
    },
    Intent(id: "bold", words: ["bold", "strong", "heavy", "textbf", "emphasis"]) { q in
        Suggestion(
            title: q.hasSelection ? "Set the selection in bold" : "Set text in bold",
            preview: "\\textbf{…}", text: "\\textbf{\(caret)}", hint: "⌘B"
        )
    },
    Intent(id: "italic", words: ["italic", "italics", "emphasise", "emphasize", "emph", "slanted"]) { q in
        Suggestion(
            title: q.hasSelection ? "Set the selection in italics" : "Set text in italics",
            preview: "\\emph{…}", text: "\\emph{\(caret)}", hint: "⌘I"
        )
    },
    Intent(id: "toc", words: ["contents", "toc", "tableofcontents", "outline", "index"]) { _ in
        Suggestion(title: "Insert a table of contents", preview: "\\tableofcontents", text: "\\tableofcontents\(caret)")
    },
    Intent(id: "abstract", words: ["abstract", "summary", "synopsis"]) { _ in
        Suggestion(title: "Insert an abstract", preview: "\\begin{abstract} … \\end{abstract}", text: "\\begin{abstract}\n  \(caret)\n\\end{abstract}")
    },
    Intent(id: "package", words: ["package", "usepackage", "import", "library", "load"]) { _ in
        Suggestion(title: "Load a package", preview: "\\usepackage{…}", text: "\\usepackage{\(caret)}")
    },
    Intent(id: "pagebreak", words: ["page", "break", "newpage", "clearpage", "next"]) { _ in
        Suggestion(title: "Break to a new page", preview: "\\newpage", text: "\\newpage\(caret)")
    },
]

private let wrappers: [Intent] = [
    Intent(id: "wrap-table", words: ["table", "turn", "convert", "selection", "into", "make"]) { _ in
        Suggestion(title: "Turn the selection into a table", preview: "rows of tab- or comma-separated text → tabular", text: "")
    },
]

/// The words of a query worth matching: letters only, so numbers (which
/// become sizes) drop out, and three letters or more, so filler such as "a",
/// "by" and "of" cannot match inside every keyword.
public func queryWords(_ text: String) -> [String] {
    text.split { !$0.isLetter }.map(String.init).filter { $0.count > 2 }
}

/// The share of `words` found among `keywords`, either way round ("pic" finds
/// "picture", "tables" finds "table"), ignoring case and accents as Finder does.
public func relevance(of words: [String], to keywords: [String]) -> Double {
    guard !words.isEmpty else { return 0 }
    let hits = words.filter { word in
        keywords.contains { $0.localizedStandardContains(word) || word.localizedStandardContains($0) }
    }
    return Double(hits.count) / Double(words.count)
}

public func suggest(_ text: String, hasSelection: Bool = false, limit: Int = 6) -> [Suggestion] {
    let words = queryWords(text)
    let q = Query(
        words: words,
        nums: text.matches(of: #/\d+/#).prefix(2).compactMap { Int($0.output) },
        hasSelection: hasSelection
    )

    let pool = hasSelection ? intents + wrappers : intents
    var out: [Suggestion] = []
    for intent in pool {
        let sc = relevance(of: words, to: intent.words)
        if sc <= 0 { continue }
        var suggestion = intent.build(q)
        suggestion.id = intent.id
        suggestion.score = sc + intent.bias
        out.append(suggestion)
    }

    out.sort { a, b in
        a.score != b.score ? a.score > b.score : a.title.localizedCompare(b.title) == .orderedAscending
    }
    return Array(out.prefix(limit))
}

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
