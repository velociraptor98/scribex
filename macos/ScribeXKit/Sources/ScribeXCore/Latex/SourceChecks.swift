// Problems found in the source itself, before any build. TeX can only report
// them by never finishing, which tells the writer nothing.

import Foundation

public func sourceIssues(_ source: String) -> [Diagnostic] {
    selfDefinitions(in: source)
}

nonisolated(unsafe) private let definitionHead =
    #/\\(?<kind>renewcommand|newcommand|providecommand|gdef|def)\*?\s*(?:\{\s*\\(?<braced>[A-Za-z]+)\s*\}|\\(?<bare>[A-Za-z]+))(?:\s*\[[^\]]*\]|\s*#\d)*\s*\{/#

/// TeX looks a command up when it is used, not when it is defined, so a body
/// that names its own command expands into itself forever:
/// `\renewcommand{\vec}[1]{\vec{\mathbf{#1}}}`. A body with a conditional may
/// be a deliberate recursion that ends, so it is left alone, as are names with
/// `@`: package-style code defines self-referential markers on purpose.
private func selfDefinitions(in source: String) -> [Diagnostic] {
    guard source.contains("def") || source.contains("command") else { return [] }
    let code = withoutComments(source)
    var out: [Diagnostic] = []

    for head in code.matches(of: definitionHead) {
        guard let name = (head.braced ?? head.bare).map(String.init),
              let body = scanBody(code, from: code.index(before: head.range.upperBound))
        else { continue }
        let words = body.words.map(\.name)
        guard words.contains(name), !words.contains(where: isConditional) else { continue }

        let line = code[..<head.range.lowerBound].unicodeScalars.count { $0 == "\n" } + 1
        // Only \renewcommand promises an earlier meaning to keep: copying a
        // command that \def is defining for the first time would fail.
        let kind = String(head.kind)
        let definition = String(code[head.range.lowerBound..<body.end])
        var fixes: [Fix] = []
        if kind == "renewcommand", !definition.unicodeScalars.contains("\n"), let saved = savedName(for: name, in: code) {
            var rewritten = definition
            for word in body.words.reversed() where word.name == name {
                let offset = code.distance(from: head.range.lowerBound, to: word.range.lowerBound)
                let start = rewritten.index(rewritten.startIndex, offsetBy: offset)
                rewritten.replaceSubrange(start..<rewritten.index(start, offsetBy: word.name.count + 1), with: "\\\(saved)")
            }
            let indent = indentation(of: line, in: code)
            fixes = [Fix(
                label: "Keep the original as \\\(saved)",
                line: line,
                find: definition,
                replace: "\\NewCommandCopy{\\\(saved)}{\\\(name)}\n\(indent)\(rewritten)"
            )]
        }

        let advice = switch kind {
        case "renewcommand":
            "To build on the original \\\(name), keep a copy of it under another name and use that inside."
        case "newcommand", "providecommand":
            "A new command has no earlier meaning to build on: use a different command inside it."
        default:
            "To build on an earlier \\\(name), keep a copy of it under another name and use that inside; "
                + "otherwise use a different command inside it."
        }
        let title = "\\\(name) is defined in terms of itself"
        out.append(Diagnostic(
            severity: .warning,
            title: title,
            detail: "TeX expands \\\(name) inside its own definition, again and again, so the build never finishes. "
                + advice,
            raw: title,
            line: line,
            fixes: fixes
        ))
    }
    return out
}

private func isConditional(_ word: String) -> Bool {
    word.hasPrefix("if") || word.hasPrefix("If") || word.hasPrefix("@if")
}

private struct Body {
    var words: [(name: String, range: Range<String.Index>)]
    /// Just past the closing brace.
    var end: String.Index
}

/// From the opening brace to its match, skipping escaped braces. Nil while the
/// body is still unbalanced, as it is mid-typing.
private func scanBody(_ code: String, from open: String.Index) -> Body? {
    var depth = 0
    var words: [(name: String, range: Range<String.Index>)] = []
    var i = open
    while i < code.endIndex {
        let c = code[i]
        if c == "\\" {
            let start = i
            i = code.index(after: i)
            guard i < code.endIndex else { return nil }
            var end = i
            while end < code.endIndex, code[end].isASCII, code[end].isLetter || code[end] == "@" {
                end = code.index(after: end)
            }
            if end > i {
                words.append((String(code[i..<end]), start..<end))
                i = end
            } else {
                i = code.index(after: i)
            }
            continue
        }
        if c == "{" { depth += 1 }
        if c == "}" {
            depth -= 1
            if depth == 0 { return Body(words: words, end: code.index(after: i)) }
        }
        i = code.index(after: i)
    }
    return nil
}

/// Comments blanked to spaces, so every line keeps its length and number.
/// Lines are split on the `\n` scalar, as elsewhere: as a `Character`, a CRLF
/// line break is not equal to `"\n"`.
private func withoutComments(_ source: String) -> String {
    source.components(separatedBy: "\n").map { line in
        var escaped = false
        for (n, c) in line.enumerated() {
            if escaped {
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else if c == "%" {
                let cr = line.hasSuffix("\r") ? "\r" : ""
                return String(line.prefix(n)) + String(repeating: " ", count: line.count - n - cr.count) + cr
            }
        }
        return line
    }.joined(separator: "\n")
}

private func savedName(for name: String, in code: String) -> String? {
    ["old", "orig", "saved"].map { $0 + name }.first { candidate in
        guard let used = try? Regex("\\\\\(candidate)(?![A-Za-z@])") else { return false }
        return code.firstMatch(of: used) == nil
    }
}

private func indentation(of line: Int, in code: String) -> String {
    let text = code.components(separatedBy: "\n")[line - 1]
    return String(text.prefix { $0 == " " || $0 == "\t" })
}
