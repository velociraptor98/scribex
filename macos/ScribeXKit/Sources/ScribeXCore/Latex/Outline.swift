import Foundation

public struct OutlineEntry: Hashable, Sendable {
    public var level: Int
    public var title: String
    public var line: Int
    /// As LaTeX would print it ("2.1"); empty for starred, unnumbered headings.
    public var number: String
}

// The title is read by brace matching below, so an empty `{}` or a nested
// `\emph{…}` inside it is taken whole.
nonisolated(unsafe) private let sectionHead = #/^\s*\\(part|chapter|section|subsection|subsubsection)(\*?)\s*(?:\[[^\]]*\])?\s*\{/#
private let levels = ["part": 0, "chapter": 1, "section": 2, "subsection": 3, "subsubsection": 4]

private func roman(_ n: Int) -> String {
    var n = n, out = ""
    for (v, r) in [(10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")] {
        while n >= v {
            out += r
            n -= v
        }
    }
    return out
}

/// Up to the brace that closes the heading's, or the rest of the line if the
/// title runs on.
private func braced(_ text: Substring) -> Substring {
    var depth = 1
    var i = text.startIndex
    while i < text.endIndex {
        switch text[i] {
        case "\\":
            i = text.index(after: i)
            if i == text.endIndex { return text }
        case "{":
            depth += 1
        case "}":
            depth -= 1
            if depth == 0 { return text[..<i] }
        default:
            break
        }
        i = text.index(after: i)
    }
    return text
}

public func outline(_ source: String) -> [OutlineEntry] {
    var heads: [(level: Int, starred: Bool, title: String, line: Int)] = []
    for (i, text) in source.components(separatedBy: "\n").enumerated() {
        guard text.contains("\\"), let m = text.firstMatch(of: sectionHead) else { continue }
        heads.append((
            level: levels[String(m.1)]!,
            starred: m.2 == "*",
            title: braced(text[m.range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines),
            line: i + 1
        ))
    }

    // Number like LaTeX: a heading resets the ones beneath it, starred headings
    // take no number, and parts count on their own without resetting chapters.
    // The dotted number starts at the shallowest level in use, so an article
    // reads 1, 1.1 rather than 0.1.
    let top = max(1, min(5, heads.filter { $0.level > 0 }.map(\.level).min() ?? 5))
    var counters = [0, 0, 0, 0, 0]
    return heads.map { h in
        if h.starred { return OutlineEntry(level: h.level, title: h.title, line: h.line, number: "") }
        counters[h.level] += 1
        if h.level > 0 {
            for k in (h.level + 1)..<counters.count { counters[k] = 0 }
        }
        let number = h.level == 0
            ? roman(counters[0])
            : top <= h.level ? counters[top...h.level].map(String.init).joined(separator: ".") : ""
        return OutlineEntry(level: h.level, title: h.title, line: h.line, number: number)
    }
}

/// The tally under the Contents panel. Counted from the source, not the log,
/// so it stays honest while a build is failing.
public struct DocStats: Hashable, Sendable {
    public var sections: Int
    public var equations: Int
    public var citations: Int

    public init(sections: Int, equations: Int, citations: Int) {
        self.sections = sections
        self.equations = equations
        self.citations = citations
    }
}

// Display maths only — inline $…$ is prose, not a numbered equation.
nonisolated(unsafe) private let equationEnvs = #/\\begin\{(equation|align|gather|multline|eqnarray|displaymath)\*?\}/#

public func stats(_ source: String) -> DocStats {
    DocStats(
        sections: outline(source).count,
        equations: source.matches(of: equationEnvs).count,
        // Distinct works cited, not \cite calls — citing one paper twice is one
        // entry in the bibliography.
        citations: citedKeys(source).count
    )
}

/// The document's \title, or its file name when it has none: how the welcome
/// window lists it.
public func documentTitle(_ source: String, path: String?) -> String {
    if let m = source.firstMatch(of: #/\\title\s*\{([^}]+)\}/#) {
        let title = m.1.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
    }
    return path.map { ($0 as NSString).lastPathComponent } ?? "untitled.tex"
}
