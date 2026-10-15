import Foundation
import Testing
@testable import ScribeXCore

struct SourceChecksTests {
    static func document(_ preamble: String) -> String {
        "\\documentclass{article}\n\(preamble)\n\\begin{document}\nx\n\\end{document}\n"
    }

    @Test func aRedefinitionThatUsesItselfOffersToKeepTheOriginal() {
        let source = Self.document("\\renewcommand{\\vec}[1]{\\vec{\\mathbf{#1}}}")
        let issues = sourceIssues(source)

        #expect(issues.count == 1)
        let d = issues[0]
        #expect(d.severity == .warning)
        #expect(d.title == "\\vec is defined in terms of itself")
        #expect(d.line == 2)
        #expect(d.fixes == [Fix(
            label: "Keep the original as \\oldvec",
            line: 2,
            find: "\\renewcommand{\\vec}[1]{\\vec{\\mathbf{#1}}}",
            replace: "\\NewCommandCopy{\\oldvec}{\\vec}\n\\renewcommand{\\vec}[1]{\\oldvec{\\mathbf{#1}}}"
        )])
    }

    @Test func everyFormOfDefinitionIsChecked() {
        for preamble in [
            "\\renewcommand\\vec[1]{\\vec{#1}}",
            "\\renewcommand*{\\vec}[1]{x\\vec{#1}}",
            "\\newcommand{\\R}{\\R^n}",
            "\\providecommand{\\R}[2][x]{\\R}",
            "\\def\\a{\\a}",
            "\\gdef\\a#1{\\a{#1}}",
        ] {
            #expect(sourceIssues(Self.document(preamble)).count == 1, "\(preamble)")
        }
    }

    @Test func aNewCommandHasNothingToKeep() {
        let d = sourceIssues(Self.document("\\newcommand{\\R}{\\R^n}"))[0]
        #expect(d.fixes.isEmpty)
        #expect(d.detail?.contains("use a different command") == true)
    }

    @Test func aDefMayBeNewSoItIsNotOfferedACopy() {
        let d = sourceIssues(Self.document("\\def\\R{\\R^n}"))[0]
        #expect(d.fixes.isEmpty)
        #expect(d.detail?.contains("otherwise use a different command") == true)
    }

    @Test func whatIsNotSelfReferenceIsLeftAlone() {
        for preamble in [
            // Another command that starts with the same letters.
            "\\renewcommand{\\vec}[1]{\\vector{#1}}",
            // A line break followed by the word, not the command.
            "\\renewcommand{\\foo}{a\\\\foo}",
            // A recursion with a way out.
            "\\def\\down#1{\\ifnum#1>0 #1 \\expandafter\\down\\expandafter{\\the\\numexpr#1-1\\relax}\\fi}",
            // \edef expands the body once, while the old meaning still stands.
            "\\edef\\a{\\a x}",
            // Package-style markers that refer to themselves on purpose.
            "\\def\\q@stop{\\q@stop}",
            // Commented out.
            "% \\renewcommand{\\vec}[1]{\\vec{#1}}",
            // Still being typed.
            "\\renewcommand{\\vec}[1]{\\vec{",
            // The original kept and used.
            "\\NewCommandCopy{\\oldvec}{\\vec}\n\\renewcommand{\\vec}[1]{\\oldvec{\\mathbf{#1}}}",
        ] {
            #expect(sourceIssues(Self.document(preamble)).isEmpty, "\(preamble)")
        }
    }

    @Test func aDefinitionOverSeveralLinesIsReportedWithoutAFix() {
        let d = sourceIssues(Self.document("\\renewcommand{\\vec}[1]{%\n  \\vec{\\mathbf{#1}}%\n}"))[0]
        #expect(d.line == 2)
        #expect(d.fixes.isEmpty)
    }

    @Test func windowsLineEndingsAreLinesToo() {
        let source = "\\documentclass{article}\r\n% a comment\r\n\\renewcommand{\\vec}[1]{\\vec{#1}}\r\n"
            + "\\begin{document}\r\nx\r\n\\end{document}\r\n"
        let issues = sourceIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.line == 3)
        #expect(issues.first?.fixes.first?.find == "\\renewcommand{\\vec}[1]{\\vec{#1}}")
    }

    @Test func theCopyTakesANameNotAlreadyInUse() {
        let d = sourceIssues(Self.document("\\newcommand{\\oldvec}{}\n\\renewcommand{\\vec}[1]{\\vec{#1}}"))[0]
        #expect(d.fixes.first?.label == "Keep the original as \\origvec")
    }

    @Test func theFixKeepsTheLinesIndentation() {
        let d = sourceIssues(Self.document("  \\renewcommand{\\vec}[1]{\\vec{#1}}"))[0]
        #expect(d.fixes.first?.replace == "\\NewCommandCopy{\\oldvec}{\\vec}\n  \\renewcommand{\\vec}[1]{\\oldvec{#1}}")
    }

    @Test func theFixBuilds() async throws {
        guard FileManager.default.isExecutableFile(atPath: TypesetterTests.worker.path) else {
            return print("skipped: build the worker with `cargo build -p scribex-engine`")
        }
        let source = "\\documentclass{article}\n\\renewcommand{\\vec}[1]{\\vec{#1}'}\n"
            + "\\begin{document}\n$\\vec{x}$\n\\end{document}\n"
        let fix = try #require(sourceIssues(source).first?.fixes.first)
        var lines = source.components(separatedBy: "\n")
        lines[fix.line - 1] = lines[fix.line - 1].replacingOccurrences(of: fix.find, with: fix.replace)
        let fixed = lines.joined(separator: "\n")
        #expect(sourceIssues(fixed).isEmpty)

        let dir = FileManager.default.temporaryDirectory.appending(path: "scribex-checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let typesetter = Typesetter(worker: TypesetterTests.worker, cpuLimit: (offline: 10, online: 10), wallLimit: 20)
        do {
            let build = try await typesetter.typeset(entry: dir.appending(path: "doc.tex"), source: fixed, onlyCached: true)
            #expect(build.pdf.starts(with: Data("%PDF".utf8)))
        } catch where error.isColdCache {
            print("skipped: the Tectonic cache is not primed")
        }
    }
}
