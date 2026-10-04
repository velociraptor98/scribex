// TeX's wording says what the parser felt, not what the writer did wrong. The
// cases worth translating get a heading, a sentence and, only where the fix is
// unambiguous, an edit to accept; anything else passes through verbatim.

import Foundation

public struct Fix: Hashable, Sendable {
    public var label: String
    /// 1-based line in the source.
    public var line: Int
    public var find: String
    public var replace: String

    public init(label: String, line: Int, find: String, replace: String) {
        self.label = label
        self.line = line
        self.find = find
        self.replace = replace
    }
}

public struct Diagnostic: Hashable, Sendable, Identifiable {
    public enum Severity: String, Sendable {
        case error, warning
    }

    public var severity: Severity
    public var title: String
    public var detail: String?
    public var raw: String
    public var line: Int?
    public var fixes: [Fix]

    public init(
        severity: Severity, title: String, detail: String? = nil, raw: String,
        line: Int? = nil, fixes: [Fix] = []
    ) {
        self.severity = severity
        self.title = title
        self.detail = detail
        self.raw = raw
        self.line = line
        self.fixes = fixes
    }

    /// Shared by de-duplication and "Ignore", so it must not change between builds.
    public var key: String {
        "\(severity.rawValue):\(title):\(line.map(String.init) ?? "")"
    }

    public var id: String { key }
}

public struct LogContext: Sendable {
    public var source: String
    public var bibKeys: [String]
    public var bibName: String?
    public var absentFiles: Set<String>

    public init(source: String = "", bibKeys: [String] = [], bibName: String? = nil, absentFiles: Set<String> = []) {
        self.source = source
        self.bibKeys = bibKeys
        self.bibName = bibName
        self.absentFiles = absentFiles
    }
}

nonisolated(unsafe) private let errorLine = #/^! (.+)$/#
nonisolated(unsafe) private let sourceLine = #/^l\.(\d+)/#
nonisolated(unsafe) private let warningLine = #/^(?:LaTeX|Package|Class)(?: (\S+))? Warning: (.+)$/#
nonisolated(unsafe) private let warningAt = #/input line (\d+)/#

nonisolated(unsafe) private let undefinedCite = #/Citation [`'"]([^'"`]+)['"`] on page \d+ undefined/#
nonisolated(unsafe) private let undefinedRef = #/Reference [`'"]([^'"`]+)['"`] on page \d+ undefined/#
nonisolated(unsafe) private let envMismatch = #/\\begin\{([^}]+)\} on input line (\d+) ended by \\end\{([^}]+)\}/#
nonisolated(unsafe) private let fileNotFound = #/File [`'"]([^'"`]+)['"`] not found/#
nonisolated(unsafe) private let overfull = #/^(Over|Under)full \\[hv]box/#

func levenshtein(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    var prev = Array(0...b.count)
    for i in a.indices {
        var cur = [i + 1]
        for j in b.indices {
            cur.append(min(prev[j + 1] + 1, cur[j] + 1, prev[j] + (a[i] == b[j] ? 0 : 1)))
        }
        prev = cur
    }
    return prev[b.count]
}

func nearest(_ target: String, in pool: [String]) -> String? {
    var best: String?
    var bestD = Int.max
    for c in pool {
        let d = levenshtein(target.lowercased(), c.lowercased())
        if d < bestD {
            bestD = d
            best = c
        }
    }
    // A third of the key may differ before the guess stops being credible.
    let allowed = max(2, Int((Double(target.count) / 3).rounded(.up)))
    return best != nil && bestD <= allowed ? best : nil
}

private func labels(in source: String) -> [String] {
    source.matches(of: #/\\label\s*\{([^}]+)\}/#).map { String($0.1) }
}

private func lineOf(_ source: String, _ needle: String, from: Int = 1) -> Int? {
    let lines = source.components(separatedBy: "\n")
    var i = from - 1
    while i < lines.count {
        if i >= 0, lines[i].contains(needle) { return i + 1 }
        i += 1
    }
    return nil
}

private func translate(_ raw: String, line: Int?, context ctx: LogContext) -> Diagnostic? {
    let src = ctx.source

    if let cite = raw.firstMatch(of: undefinedCite) {
        let key = String(cite.1)
        let guess = nearest(key, in: ctx.bibKeys)
        let at = line ?? lineOf(src, "{\(key)}") ?? lineOf(src, key)
        let detail = guess.map { guess in
            "Nothing in your bibliography matches. ScribeX found \(guess)"
                + (ctx.bibName.map { " in \($0)" } ?? "") + "."
        } ?? "Nothing in your bibliography matches this key."
        var fixes: [Fix] = []
        if let guess, let at { fixes = [Fix(label: "Use \(guess)", line: at, find: key, replace: guess)] }
        return Diagnostic(
            severity: .warning, title: "No such reference: \(key)", detail: detail,
            raw: raw, line: at, fixes: fixes
        )
    }

    if let ref = raw.firstMatch(of: undefinedRef) {
        let key = String(ref.1)
        let guess = nearest(key, in: labels(in: src))
        let at = line ?? lineOf(src, "{\(key)}")
        let detail = guess.map { "No \\label{\(key)} is defined. The closest one is \($0)." }
            ?? "No \\label with this key is defined, so the number cannot be resolved."
        var fixes: [Fix] = []
        if let guess, let at { fixes = [Fix(label: "Use \(guess)", line: at, find: key, replace: guess)] }
        return Diagnostic(
            severity: .warning, title: "No such label: \(key)", detail: detail,
            raw: raw, line: at, fixes: fixes
        )
    }

    if let env = raw.firstMatch(of: envMismatch) {
        let opened = String(env.1), closed = String(env.3)
        let openLine = Int(env.2) ?? 1
        let closeLine = lineOf(src, "\\end{\(closed)}", from: openLine)
        return Diagnostic(
            severity: .error,
            title: "\(opened) opened, \(closed) closed",
            detail: "The environment names differ. Match them and the equation will number itself.",
            raw: raw,
            line: openLine,
            fixes: closeLine.map {
                [Fix(label: "Fix both to \(opened)", line: $0, find: "\\end{\(closed)}", replace: "\\end{\(opened)}")]
            } ?? []
        )
    }

    if let missing = raw.firstMatch(of: fileNotFound), ctx.absentFiles.contains(String(missing.1)) {
        return Diagnostic(
            severity: .error,
            title: "Missing file: \(missing.1)",
            detail: "The document expects \(missing.1) beside it. It is not part of the TeX distribution, so it cannot be downloaded: put it in the document's folder.",
            raw: raw,
            line: line
        )
    }

    if let missing = raw.firstMatch(of: fileNotFound) {
        return Diagnostic(
            severity: .error,
            title: "Not in the cache: \(missing.1)",
            detail: "This resource is not on the machine. Fetch it once and it stays available offline.",
            raw: raw,
            line: line
        )
    }

    if raw.hasPrefix("Undefined control sequence") {
        return Diagnostic(
            severity: .error,
            title: "Unknown command",
            detail: "TeX does not recognise this command. Check the spelling, or load the package that defines it.",
            raw: raw,
            line: line
        )
    }

    if raw.hasPrefix("Missing $ inserted") {
        return Diagnostic(
            severity: .error,
            title: "Maths outside maths mode",
            detail: "A symbol that only exists in maths appeared in prose. Wrap it in $…$.",
            raw: raw,
            line: line
        )
    }

    if raw.hasPrefix("Missing } inserted") || raw.hasPrefix("Missing { inserted") {
        return Diagnostic(
            severity: .error,
            title: "Unbalanced braces",
            detail: "A group was opened and never closed.",
            raw: raw,
            line: line
        )
    }

    if raw.hasPrefix("Runaway argument") {
        return Diagnostic(
            severity: .error,
            title: "Runaway argument",
            detail: "A command's argument was never closed, so TeX read to the end of the document looking for the brace.",
            raw: raw,
            line: line
        )
    }

    return nil
}

private func trimmed(_ s: Substring) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
}

public func parseLog(_ log: String, context ctx: LogContext = LogContext()) -> [Diagnostic] {
    let lines = log.components(separatedBy: "\n")
    var out: [Diagnostic] = []

    for (i, line) in lines.enumerated() {
        let next = i + 1 < lines.count ? lines[i + 1].trimmingCharacters(in: .whitespacesAndNewlines) : nil

        // Cheap guards first: a log runs to thousands of lines and few are marks.
        if line.hasPrefix("! "), let err = line.firstMatch(of: errorLine) {
            // TeX prints the offending source line a few lines below the message,
            // and often wraps the message itself onto the next line.
            var at: Int?
            for j in (i + 1)..<min(i + 12, lines.count) {
                if let m = lines[j].firstMatch(of: sourceLine) {
                    at = Int(m.1)
                    break
                }
            }
            var raw = trimmed(err.1)
            if let cont = next, !cont.isEmpty, !"l!(".contains(cont.first!) {
                raw = "\(raw) \(cont)"
            }
            // Tectonic's log can double the marker: "! ! LaTeX Error: …".
            if let prefix = raw.firstMatch(of: #/^(?:!\s+)*LaTeX Error:\s*/#) {
                raw.removeSubrange(prefix.range)
            }

            out.append(
                translate(raw, line: at, context: ctx)
                    ?? Diagnostic(severity: .error, title: raw, raw: raw, line: at)
            )
            continue
        }

        if line.contains(" Warning: "), let warn = line.firstMatch(of: warningLine) {
            var full = String(warn.2)
            if let cont = next, !cont.isEmpty, !cont.hasPrefix("("), !cont.hasPrefix("!") {
                full = "\(full) \(cont)"
            }
            let raw = full.trimmingCharacters(in: .whitespacesAndNewlines)
            let at = raw.firstMatch(of: warningAt).flatMap { Int($0.1) }
            out.append(
                translate(raw, line: at, context: ctx)
                    ?? Diagnostic(severity: .warning, title: raw, raw: raw, line: at)
            )
        }
    }

    // One mark per problem: TeX repeats an undefined citation on every page.
    var seen = Set<String>()
    return out.filter { seen.insert($0.key).inserted }
}

public struct PressRow: Hashable, Sendable, Identifiable {
    public var stage: String
    public var detail: String
    public var flagged: Bool

    public init(stage: String, detail: String, flagged: Bool = false) {
        self.stage = stage
        self.detail = detail
        self.flagged = flagged
    }

    public var id: String { stage }
}

nonisolated(unsafe) private let citeCall = #/\\cite\w*\s*(?:\[[^\]]*\])*\{([^}]*)\}/#
nonisolated(unsafe) private let labelCall = #/\\label\s*\{[^}]+\}/#

private func plural(_ n: Int, _ word: String) -> String {
    "\(n) \(word)\(n > 1 ? "s" : "")"
}

/// Per-stage findings, not timings: Tectonic runs its passes internally and
/// reports only the total duration.
public func pressLog(
    _ log: String, source: String = "", name: String = "document.tex", diags: [Diagnostic] = []
) -> [PressRow] {
    let stem = name.replacing(#/(?i)\.tex$/#, with: "")
    var rows: [PressRow] = []

    rows.append(PressRow(stage: "typeset", detail: "\(name) → \(stem).pdf"))

    let cited = Set(
        source.matches(of: citeCall)
            .flatMap { $0.1.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.isEmpty }
    )
    if !cited.isEmpty {
        let unresolved = diags.filter { $0.title.hasPrefix("No such reference") }.count
        rows.append(PressRow(
            stage: "bibliography",
            detail: unresolved > 0
                ? plural(unresolved, "unresolved key")
                : "\(plural(cited.count, "key")) resolved",
            flagged: unresolved > 0
        ))
    }

    let labelCount = source.matches(of: labelCall).count
    if labelCount > 0 {
        let dangling = diags.filter { $0.title.hasPrefix("No such label") }.count
        let rerun = log.contains("Label(s) may have changed")
        rows.append(PressRow(
            stage: "cross-refs",
            detail: rerun
                ? "labels moved — rebuilt to settle"
                : dangling > 0 ? "\(dangling) unresolved" : "\(plural(labelCount, "label")) resolved",
            flagged: dangling > 0
        ))
    }

    let overfullCount = log.components(separatedBy: "\n").filter { $0.firstMatch(of: overfull) != nil }.count
    if overfullCount > 0 {
        rows.append(PressRow(
            stage: "justification",
            detail: "\(plural(overfullCount, "line")) outside the measure",
            flagged: true
        ))
    }

    return rows
}
