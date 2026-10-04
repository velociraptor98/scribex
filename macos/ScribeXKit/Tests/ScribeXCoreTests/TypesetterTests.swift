import Foundation
import Testing
@testable import ScribeXCore

/// Runs the real Rust worker. Needs `cargo build -p scribex-engine` and a
/// primed Tectonic cache, since builds run offline; without either the tests
/// report why and pass.
struct TypesetterTests {
    static let worker = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "../../../../target/debug/scribex-typeset")
        .standardized

    static let hello = "\\documentclass{article}\n\\begin{document}\nHello.\n\\end{document}\n"

    func project() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "scribex-typesetter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var available: Bool {
        if FileManager.default.isExecutableFile(atPath: Self.worker.path) { return true }
        print("skipped: build the worker with `cargo build -p scribex-engine`")
        return false
    }

    @Test func buildsAPDFWithoutTouchingTheDocument() async throws {
        guard available else { return }
        let dir = try project()
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = dir.appending(path: "doc.tex")

        do {
            let build = try await Typesetter(worker: Self.worker).typeset(entry: entry, source: Self.hello, onlyCached: true)
            #expect(build.pdf.starts(with: Data("%PDF".utf8)))
            #expect(build.log.contains("Hello") || !build.log.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: entry.path), "the buffer is typeset, the file left alone")
        } catch where error.isColdCache {
            print("skipped: the Tectonic cache is not primed")
        }
    }

    @Test func aBrokenDocumentReportsItsLog() async throws {
        guard available else { return }
        let dir = try project()
        defer { try? FileManager.default.removeItem(at: dir) }

        do {
            _ = try await Typesetter(worker: Self.worker).typeset(
                entry: dir.appending(path: "bad.tex"),
                source: "\\documentclass{article}\n\\begin{document}\n\\nosuchcommand\n\\end{document}\n",
                onlyCached: true
            )
            Issue.record("expected the build to fail")
        } catch where error.isColdCache {
            print("skipped: the Tectonic cache is not primed")
        } catch {
            #expect(!error.superseded)
            #expect(parseLog(error.log).contains { $0.title == "Unknown command" && $0.line == 3 })
        }
    }

    @Test func aClassBesideTheDocumentIsAbsentNotMissing() async throws {
        guard available else { return }
        let dir = try project()
        defer { try? FileManager.default.removeItem(at: dir) }

        do {
            _ = try await Typesetter(worker: Self.worker).typeset(
                entry: dir.appending(path: "cv.tex"),
                source: "\\documentclass{scribex-own-class}\n\\begin{document}x\\end{document}\n",
                onlyCached: true
            )
            Issue.record("expected the build to fail")
        } catch where error.isColdCache {
            print("skipped: the Tectonic cache is not primed")
        } catch {
            #expect(error.missingFile == nil)
            #expect(error.absentFile == "scribex-own-class.cls")
        }
    }

    @Test func queuedPreviewsAreDroppedOnceSuperseded() async throws {
        guard available else { return }
        let dir = try project()
        defer { try? FileManager.default.removeItem(at: dir) }
        let typesetter = Typesetter(worker: Self.worker)
        let entry = dir.appending(path: "doc.tex")

        // The first takes the slot; the second queues behind it and is
        // overtaken by the third before it can run.
        async let first = outcome(typesetter, entry)
        try await Task.sleep(for: .milliseconds(50))
        async let second = outcome(typesetter, entry)
        try await Task.sleep(for: .milliseconds(50))
        async let third = outcome(typesetter, entry)

        let results = await [first, second, third]
        if results.contains("cold") { return print("skipped: the Tectonic cache is not primed") }
        #expect(results == ["built", "superseded", "built"])
    }

    private func outcome(_ typesetter: Typesetter, _ entry: URL) async -> String {
        do {
            _ = try await typesetter.typeset(entry: entry, source: Self.hello, onlyCached: true)
            return "built"
        } catch {
            return error.superseded ? "superseded" : error.isColdCache ? "cold" : error.message
        }
    }

    @Test func warmupDocumentComesFromTheEngine() async throws {
        guard available else { return }
        let doc = try await Typesetter.warmupDocument(Self.worker)
        #expect(doc.hasPrefix("\\documentclass{article}"))
        #expect(doc.contains("\\maketitle"))
    }

    @Test func saveAndExport() throws {
        let dir = try project()
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = dir.appending(path: "nested/doc.tex")

        try saveDocument("hello", to: entry)
        #expect(try String(contentsOf: entry, encoding: .utf8) == "hello")

        #expect(throws: FileError.self) { try exportPDF(for: entry, to: dir.appending(path: "out.pdf")) }
        try FileManager.default.createDirectory(at: Typesetter.outputDirectory(for: entry), withIntermediateDirectories: true)
        try Data("%PDF-x".utf8).write(to: Typesetter.pdfURL(for: entry))
        #expect(try exportPDF(for: entry, to: dir.appending(path: "out.pdf")) == 6)
    }
}
