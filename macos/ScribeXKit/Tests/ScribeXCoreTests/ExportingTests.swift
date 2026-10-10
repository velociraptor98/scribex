import Foundation
import Testing
@testable import ScribeXCore

struct ExportingTests {
    @Test func sheetReplacesAnyPaperOptionAndKeepsTheRest() {
        #expect(withSheet("\\documentclass{article}", .a4) == "\\documentclass[a4paper]{article}")
        #expect(withSheet("\\documentclass[12pt, A5paper,twoside]{book}", .letter) == "\\documentclass[12pt,twoside,letterpaper]{book}")
        #expect(withSheet("no class here", .a4) == "no class here")
    }

    @Test func hyperrefGoesLastInThePreambleOnce() {
        let doc = "\\documentclass{article}\n\\begin{document}\nx\n\\end{document}"
        #expect(withHyperref(doc) == "\\documentclass{article}\n\\usepackage{hyperref}\n\\begin{document}\nx\n\\end{document}")
        let loaded = "\\usepackage{amsmath,hyperref}\n\\begin{document}"
        #expect(withHyperref(loaded) == loaded)
    }

    @Test func sheetOfReadsTheClassOption() {
        #expect(sheetOf("\\documentclass[a4paper,12pt]{article}") == .a4)
        #expect(sheetOf("\\documentclass{article}") == .letter)
    }

    @Test func onlyOptionsThatChangeTheDocumentRebuild() {
        #expect(!ExportOptions(sheet: .a4, sourceAlongside: true).needsRebuild(documentSheet: .a4))
        #expect(ExportOptions(sheet: .a5).needsRebuild(documentSheet: .a4))
        #expect(ExportOptions(sheet: .a4, hyperlinks: true).needsRebuild(documentSheet: .a4))
    }
}

struct RecentTests {
    @Test func titleFallsBackToTheFileName() {
        #expect(documentTitle("\\title{ On Proofs }", path: "/x/a.tex") == "On Proofs")
        #expect(documentTitle("\\title{}", path: "/x/a.tex") == "a.tex")
        #expect(documentTitle("", path: nil) == "untitled.tex")
    }
}
