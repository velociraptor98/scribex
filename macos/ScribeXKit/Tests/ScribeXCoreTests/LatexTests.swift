import Foundation
import Testing
@testable import ScribeXCore

struct LatexTests {
    @Test func articleNumbersFromSections() {
        let source = """
            \\section{Introduction}
            \\subsection{Background}
            \\subsection*{Aside}
            \\section{Method}
            \\subsection{Setup}
            """
        #expect(outline(source).map(\.number) == ["1", "1.1", "", "2", "2.1"])
        #expect(outline(source).map(\.line) == [1, 2, 3, 4, 5])
    }

    @Test func bookNumbersFromChapters() {
        let source = "\\chapter{One}\n\\section{A}\n\\chapter{Two}\n\\section{B}\n"
        #expect(outline(source).map(\.number) == ["1", "1.1", "2", "2.1"])
    }

    @Test func partsCountInRomanWithoutResettingChapters() {
        let source = "\\part{I}\n\\chapter{a}\n\\part{II}\n\\chapter{b}\n"
        #expect(outline(source).map(\.number) == ["I", "1", "II", "2"])
    }

    @Test func titlesAreBraceMatched() {
        let entries = outline("\\section[short]{A \\emph{nested} title} trailing\n\\section{}\n")
        #expect(entries.map(\.title) == ["A \\emph{nested} title", ""])
    }

    @Test func statsCountDistinctCitations() {
        let source = """
            \\section{A}
            \\begin{equation}x\\end{equation}
            \\begin{align*}y\\end{align*}
            $inline$ \\cite{a, b} \\citep[p. 2]{a}
            """
        #expect(stats(source) == DocStats(sections: 1, equations: 2, citations: 2))
    }

    @Test func bibKeysAndFiles() {
        #expect(bibKeys("@article{smith2020,\n title={x}}\n@book{ jones ,}") == ["smith2020", "jones"])
        #expect(bibliographyFiles("\\bibliography{refs, more.bib}\\addbibresource{extra}") == ["refs.bib", "more.bib", "extra.bib"])
    }

    @Test func syntaxTokens() {
        let text = "\\begin{equation} $x$ % note\n\\{ \\[" as NSString
        var found: [(String, LatexToken)] = []
        latexTokens(in: text, range: NSRange(location: 0, length: text.length)) { range, kind in
            found.append((text.substring(with: range), kind))
        }

        #expect(found.map(\.0) == ["\\begin", "{", "equation", "}", "$", "$", "% note", "\\{", "\\["])
        #expect(found.map(\.1) == [.command, .bracket, .environment, .bracket, .math, .math, .comment, .command, .math])
    }
}
