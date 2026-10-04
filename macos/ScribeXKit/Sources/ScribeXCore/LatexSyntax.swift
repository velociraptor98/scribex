import Foundation

/// What the editor colours, in the spirit of CodeMirror's `stex` mode that the
/// React app used: commands, environment names, maths delimiters, brackets and
/// comments. Everything else is prose.
public enum LatexToken: Sendable {
    case command
    case environment
    case math
    case bracket
    case comment
}

/// Scan `range` of `text` and report each token found, in order.
///
/// Works in UTF-16 offsets, which is what the text view speaks. Every token
/// ends at a line break, so any range that starts at the beginning of a line
/// can be scanned on its own — the editor re-scans only the lines an edit
/// touched.
public func latexTokens(in text: NSString, range: NSRange, _ found: (NSRange, LatexToken) -> Void) {
    let end = range.location + range.length
    var i = range.location

    func at(_ k: Int) -> unichar { k < end ? text.character(at: k) : 0 }
    func isLetter(_ c: unichar) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) }
    let newline: unichar = 10, backslash: unichar = 92, percent: unichar = 37, dollar: unichar = 36
    let openBrace: unichar = 123, closeBrace: unichar = 125, openBracket: unichar = 91, closeBracket: unichar = 93
    let openParen: unichar = 40, closeParen: unichar = 41, space: unichar = 32, tab: unichar = 9

    while i < end {
        let c = text.character(at: i)
        switch c {
        case percent:
            var j = i
            while j < end, text.character(at: j) != newline { j += 1 }
            found(NSRange(location: i, length: j - i), .comment)
            i = j

        case backslash:
            let next = at(i + 1)
            if isLetter(next) {
                var j = i + 1
                while j < end, isLetter(text.character(at: j)) { j += 1 }
                found(NSRange(location: i, length: j - i), .command)
                let name = text.substring(with: NSRange(location: i + 1, length: j - i - 1))
                i = j
                // \begin{name} and \end{name}: the name is the environment.
                if name == "begin" || name == "end" {
                    var k = i
                    while k < end, at(k) == space || at(k) == tab { k += 1 }
                    if at(k) == openBrace {
                        var close = k + 1
                        while close < end, at(close) != closeBrace, at(close) != newline { close += 1 }
                        found(NSRange(location: k, length: 1), .bracket)
                        if close > k + 1 { found(NSRange(location: k + 1, length: close - k - 1), .environment) }
                        if at(close) == closeBrace {
                            found(NSRange(location: close, length: 1), .bracket)
                            close += 1
                        }
                        i = close
                    }
                }
            } else if next == openBracket || next == closeBracket || next == openParen || next == closeParen {
                found(NSRange(location: i, length: 2), .math)
                i += 2
            } else if next != 0 && next != newline {
                // An escaped character (\%, \{, \\) or a control symbol.
                found(NSRange(location: i, length: 2), .command)
                i += 2
            } else {
                found(NSRange(location: i, length: 1), .command)
                i += 1
            }

        case dollar:
            let length = at(i + 1) == dollar ? 2 : 1
            found(NSRange(location: i, length: length), .math)
            i += length

        case openBrace, closeBrace, openBracket, closeBracket:
            found(NSRange(location: i, length: 1), .bracket)
            i += 1

        default:
            i += 1
        }
    }
}
