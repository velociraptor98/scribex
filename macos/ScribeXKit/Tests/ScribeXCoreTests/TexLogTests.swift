import Testing
@testable import ScribeXCore

struct TexLogTests {
    @Test func undefinedCitationProposesTheNearestBibKey() {
        let source = "\\documentclass{article}\n\\begin{document}\nAs shown \\cite{smth2020}.\n\\end{document}\n"
        let log = "LaTeX Warning: Citation `smth2020' on page 1 undefined on input line 3.\n"
        let diags = parseLog(log, context: LogContext(source: source, bibKeys: ["smith2020", "jones1999"], bibName: "refs.bib"))

        #expect(diags.count == 1)
        let d = diags[0]
        #expect(d.severity == .warning)
        #expect(d.title == "No such reference: smth2020")
        #expect(d.detail == "Nothing in your bibliography matches. ScribeX found smith2020 in refs.bib.")
        #expect(d.line == 3)
        #expect(d.fixes == [Fix(label: "Use smith2020", line: 3, find: "smth2020", replace: "smith2020")])
    }

    @Test func undefinedReferenceProposesTheNearestLabel() {
        let source = "\\section{A}\\label{sec:intro}\nSee \\ref{sec:intr}.\n"
        let log = "LaTeX Warning: Reference `sec:intr' on page 1 undefined on input line 2.\n"
        let d = parseLog(log, context: LogContext(source: source))[0]

        #expect(d.title == "No such label: sec:intr")
        #expect(d.fixes.first?.replace == "sec:intro")
    }

    @Test func noGuessWhenNothingIsClose() {
        let log = "LaTeX Warning: Citation `zzz' on page 1 undefined on input line 3.\n"
        let d = parseLog(log, context: LogContext(source: "", bibKeys: ["knuth1984"]))[0]

        #expect(d.detail == "Nothing in your bibliography matches this key.")
        #expect(d.fixes.isEmpty)
    }

    @Test func mismatchedEnvironmentOffersToFixTheEnd() {
        let source = "a\n\\begin{equation}\nx\n\\end{align}\n"
        let log = """
            ! LaTeX Error: \\begin{equation} on input line 2 ended by \\end{align}.

            See the LaTeX manual or LaTeX Companion for explanation.
            l.4 \\end{align}

            """
        let d = parseLog(log, context: LogContext(source: source))[0]

        #expect(d.severity == .error)
        #expect(d.title == "equation opened, align closed")
        #expect(d.line == 2)
        #expect(d.fixes == [Fix(label: "Fix both to equation", line: 4, find: "\\end{align}", replace: "\\end{equation}")])
    }

    @Test func errorTakesTheSourceLineFromBelowIt() {
        let log = """
            ! Undefined control sequence.
            <recently read> \\foo

            l.7 \\foo
                     bar
            """
        let d = parseLog(log)[0]

        #expect(d.title == "Unknown command")
        #expect(d.line == 7)
        #expect(d.raw == "Undefined control sequence. <recently read> \\foo")
    }

    @Test func missingFileIsReportedAsNotCached() {
        let log = "! LaTeX Error: File `tikz.sty' not found.\n\nType X to quit.\n"
        let d = parseLog(log)[0]

        #expect(d.title == "Not in the cache: tikz.sty")
        #expect(d.raw.hasPrefix("File `tikz.sty' not found."))
    }

    @Test func aFileNoDownloadCanSupplyIsNotOfferedAsOne() {
        let log = "! ! LaTeX Error: File `resume.cls' not found..\n\nType X to quit.\n"
        let d = parseLog(log, context: LogContext(absentFiles: ["resume.cls"]))[0]

        #expect(d.raw == "File `resume.cls' not found..")

        #expect(d.title == "Missing file: resume.cls")
        #expect(d.detail?.contains("cannot be downloaded") == true)
    }

    @Test func untranslatedMessagesPassThroughVerbatim() {
        let d = parseLog("! Something nobody anticipated.\n")[0]
        #expect(d.title == "Something nobody anticipated.")
        #expect(d.detail == nil)
    }

    @Test func repeatedWarningsCollapseToOneMark() {
        let line = "LaTeX Warning: Citation `a' on page 1 undefined on input line 3.\n"
        #expect(parseLog(line + line + line).count == 1)
    }

    @Test func pressLogReportsWhatTheRunFound() {
        let source = "\\cite{a,b}\\label{x}\\label{y}"
        let log = "Overfull \\hbox (3.0pt too wide) in paragraph\nUnderfull \\vbox (badness 10000)\n"
        let rows = pressLog(log, source: source, name: "paper.tex")

        #expect(rows == [
            PressRow(stage: "typeset", detail: "paper.tex → paper.pdf"),
            PressRow(stage: "bibliography", detail: "2 keys resolved"),
            PressRow(stage: "cross-refs", detail: "2 labels resolved"),
            PressRow(stage: "justification", detail: "2 lines outside the measure", flagged: true),
        ])
    }

    @Test func pressLogFlagsUnresolvedKeys() {
        let diags = [Diagnostic(severity: .warning, title: "No such reference: a", raw: "")]
        let rows = pressLog("", source: "\\cite{a}", diags: diags)
        #expect(rows[1] == PressRow(stage: "bibliography", detail: "1 unresolved key", flagged: true))
    }

    @Test func levenshteinDistance() {
        #expect(levenshtein("kitten", "sitting") == 3)
        #expect(levenshtein("", "abc") == 3)
        #expect(levenshtein("abc", "") == 3)
        #expect(levenshtein("same", "same") == 0)
    }
}
