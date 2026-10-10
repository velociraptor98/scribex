// The vocabulary lives in snippets.json: each snippet's trigger words, title
// and LaTeX. Matching is a local keyword score, so synonyms there matter more
// than clever ranking here.

import Foundation

/// Where the caret should land after an insertion. Stripped before insert.
public let caret = "\u{2038}"

/// A snippet ready to insert. How well it fits a query is not part of it:
/// that is `relevance`, worked out by whoever is ranking.
public struct Suggestion: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var preview: String?
    public var hint: String?
    /// Empty for "turn the selection into a table", which the caller builds
    /// from the selection itself.
    public var text: String
    /// The trigger words it matches on.
    public var words: [String]
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

private let entries: [Entry] = bundled("snippets.json")

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
        id: entry.id,
        title: fill(q.hasSelection ? entry.selectionTitle ?? entry.title : entry.title),
        preview: entry.preview.map(fill), hint: entry.hint, text: text, words: entry.words
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

/// How well typed `words` fit an item's `keywords`, from 0 (not at all) up:
/// 2 for each word matched exactly, 1 for a prefix either way, averaged over
/// the words. One rule for snippets and commands alike, so they rank together.
public func relevance(of keywords: [String], to words: [String]) -> Double {
    if words.isEmpty { return 0 }
    var hits = 0
    for w in words {
        for k in keywords {
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
    // Averaged over the query, so a long keyword list is no advantage.
    return Double(hits) / Double(words.count)
}

public func suggest(_ text: String, hasSelection: Bool = false, limit: Int = 6) -> [Suggestion] {
    let words = tokenize(text)
    let q = Query(
        words: words,
        nums: text.matches(of: #/\d+/#).prefix(2).compactMap { Int($0.output) },
        hasSelection: hasSelection
    )

    // Best first; `bias` only settles ties, then the title does.
    return entries
        .filter { hasSelection || $0.needsSelection != true }
        .map { (entry: $0, fit: relevance(of: $0.words, to: words)) }
        .filter { $0.fit > 0 }
        .sorted { a, b in
            let x = a.fit + (a.entry.bias ?? 0), y = b.fit + (b.entry.bias ?? 0)
            return x != y ? x > y : a.entry.title.localizedCompare(b.entry.title) == .orderedAscending
        }
        .prefix(limit)
        .map { build($0.entry, q) }
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
