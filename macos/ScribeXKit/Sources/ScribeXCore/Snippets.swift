// The vocabulary lives in snippets.json: each snippet's trigger words, title
// and LaTeX. Matching is a local keyword score, so synonyms there matter more
// than clever ranking here.

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

/// One snippet from snippets.json. `text` is inserted as is; `generator`
/// instead names a snippet built from the query's numbers.
private struct Entry: Decodable, Sendable {
    var id: String
    /// Matched loosely, by prefix in either direction.
    var words: [String]
    /// Breaks ties toward the plainer reading: "a table" matches both `table`
    /// and `booktabs` equally. Too small to overturn a better keyword match.
    var bias: Double?
    /// May use {columns}, {rows} ("3 columns"), {c}, {r} ("3") and {spec} ("lll").
    var title: String
    var selectionTitle: String?
    var preview: String?
    var text: String?
    var generator: String?
    var hint: String?
    /// Offered only while text is selected.
    var needsSelection: Bool?
}

/// Bundled with the app, so a file that fails to load is a build mistake.
private let entries: [Entry] = {
    let url = Bundle.module.url(forResource: "snippets", withExtension: "json", subdirectory: "Resources")!
    return try! JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
}()

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

private func matrix(_ c: Int, _ r: Int) -> String {
    let body = (0..<r).map { _ in Array(repeating: "0", count: c).joined(separator: " & ") }
        .joined(separator: " \\\\\n  ")
    return "\\begin{pmatrix}\n  \(body)\n\\end{pmatrix}\(caret)"
}

private func build(_ entry: Entry, _ q: Query) -> Suggestion {
    let c = q.cols, r = q.rows
    func fill(_ template: String) -> String {
        template
            .replacingOccurrences(of: "{columns}", with: "\(c) column\(s(c))")
            .replacingOccurrences(of: "{rows}", with: "\(r) row\(s(r))")
            .replacingOccurrences(of: "{spec}", with: String(repeating: "l", count: c))
            .replacingOccurrences(of: "{c}", with: "\(c)")
            .replacingOccurrences(of: "{r}", with: "\(r)")
    }
    let text = switch entry.generator {
    case "tabular": tabular(c, r, booktabs: false)
    case "booktabs": tabular(c, r, booktabs: true)
    case "matrix": matrix(c, r)
    default: entry.text ?? ""
    }
    return Suggestion(
        title: fill(q.hasSelection ? entry.selectionTitle ?? entry.title : entry.title),
        preview: entry.preview.map(fill), text: text, hint: entry.hint
    )
}

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

private func score(_ entry: Entry, _ words: [String]) -> Double {
    if words.isEmpty { return 0 }
    var hits = 0
    for w in words {
        for k in entry.words {
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

public func suggest(_ text: String, hasSelection: Bool = false, limit: Int = 6) -> [Suggestion] {
    let words = tokenize(text)
    let q = Query(
        words: words,
        nums: text.matches(of: #/\d+/#).prefix(2).compactMap { Int($0.output) },
        hasSelection: hasSelection
    )

    var out: [Suggestion] = []
    for entry in entries where hasSelection || entry.needsSelection != true {
        let sc = score(entry, words)
        if sc <= 0 { continue }
        var suggestion = build(entry, q)
        suggestion.id = entry.id
        suggestion.score = sc + (entry.bias ?? 0)
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
