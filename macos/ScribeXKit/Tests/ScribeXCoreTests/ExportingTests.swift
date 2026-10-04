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

    @Test func relativeTimes() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        #expect(when(now.addingTimeInterval(-20), now: now) == "Just now")
        #expect(when(now.addingTimeInterval(-120), now: now) == "2 min ago")
        #expect(when(now.addingTimeInterval(-3600), now: now) == "1 hour ago")
        #expect(when(now.addingTimeInterval(-30 * 3600), now: now) == "Yesterday")
        #expect(when(Date(timeIntervalSince1970: 1_754_222_400), now: now) == "3 Aug")
    }

    @Test func rememberMovesADocumentToTheTopAndCaps() {
        let suite = "scribex-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = RecentStore(suite: suite)

        for i in 0..<10 { store.remember(RecentDoc(path: "/d\(i).tex", title: "\(i)", sections: 0, citations: 0)) }
        let list = store.remember(RecentDoc(path: "/d3.tex", title: "again", sections: 1, citations: 0))

        #expect(list.count == RecentStore.limit)
        #expect(list.first?.title == "again")
        #expect(store.load().map(\.path).filter { $0 == "/d3.tex" }.count == 1)
    }
}
