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

    @Test func supersededPreviewsAreDroppedOrStopped() async throws {
        guard available else { return }
        let dir = try project()
        defer { try? FileManager.default.removeItem(at: dir) }
        let typesetter = Typesetter(worker: Self.worker)
        let entry = dir.appending(path: "doc.tex")

        // The first is stopped while it runs; the second is overtaken by the
        // third, whether it is still queued or already running by then.
        async let first = outcome(typesetter, entry)
        try await Task.sleep(for: .milliseconds(50))
        async let second = outcome(typesetter, entry)
        try await Task.sleep(for: .milliseconds(50))
        async let third = outcome(typesetter, entry)

        let results = await [first, second, third]
        if results.contains("cold") { return print("skipped: the Tectonic cache is not primed") }
        #expect(results == ["superseded", "superseded", "built"])
    }

    @Test func aPreviewNeverSupersedesAnotherDocument() async throws {
        guard available else { return }
        let dir = try project()
        defer { try? FileManager.default.removeItem(at: dir) }
        let typesetter = Typesetter(worker: Self.worker)

        // Two documents in one folder share a build directory, so they queue,
        // but neither drops the other.
        async let first = outcome(typesetter, dir.appending(path: "a.tex"))
        try await Task.sleep(for: .milliseconds(50))
        async let second = outcome(typesetter, dir.appending(path: "b.tex"))

        let results = await [first, second]
        if results.contains("cold") { return print("skipped: the Tectonic cache is not primed") }
        #expect(results == ["built", "built"])
    }

    static let loops = "\\documentclass{article}\n\\renewcommand{\\vec}[1]{\\vec{\\mathbf{#1}}}\n"
        + "\\begin{document}\n$\\vec{x}$\n\\end{document}\n"

    @Test func aDocumentThatLoopsForeverIsStoppedByItsCPULimit() async throws {
        guard available else { return }
        let dir = try project()
        defer { try? FileManager.default.removeItem(at: dir) }
        let typesetter = Typesetter(worker: Self.worker, cpuLimit: (offline: 1, online: 1), wallLimit: 60)

        let result = await outcome(typesetter, dir.appending(path: "doc.tex"), source: Self.loops)
        if result == "cold" { return print("skipped: the Tectonic cache is not primed") }
        #expect(result == "timed out: Stopped after 1 s")
    }

    @Test func aDocumentThatLoopsForeverIsStoppedByItsWallClockLimit() async throws {
        guard available else { return }
        let dir = try project()
        defer { try? FileManager.default.removeItem(at: dir) }
        let typesetter = Typesetter(worker: Self.worker, cpuLimit: (offline: 60, online: 60), wallLimit: 1)

        let result = await outcome(typesetter, dir.appending(path: "doc.tex"), source: Self.loops)
        if result == "cold" { return print("skipped: the Tectonic cache is not primed") }
        #expect(result == "timed out: Stopped after 1 s")
    }

    @Test func fixingADocumentThatLoopsStopsTheLoop() async throws {
        guard available else { return }
        let dir = try project()
        defer { try? FileManager.default.removeItem(at: dir) }
        let typesetter = Typesetter(worker: Self.worker)
        let entry = dir.appending(path: "doc.tex")

        let started = ContinuousClock.now
        async let looping = outcome(typesetter, entry, source: Self.loops)
        try await Task.sleep(for: .milliseconds(500))
        async let fixed = outcome(typesetter, entry)

        let results = await [looping, fixed]
        if results.contains("cold") { return print("skipped: the Tectonic cache is not primed") }
        #expect(results == ["superseded", "built"])
        #expect(ContinuousClock.now - started < .seconds(30))
    }

    @Test func aDocumentThatLoopsHoldsUpNoOtherFolder() async throws {
        guard available else { return }
        let dir = try project(), other = try project()
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: other)
        }
        let typesetter = Typesetter(worker: Self.worker)

        let looping = Task { await outcome(typesetter, dir.appending(path: "doc.tex"), source: Self.loops) }
        defer { looping.cancel() }
        try await Task.sleep(for: .milliseconds(500))

        let result = await outcome(typesetter, other.appending(path: "doc.tex"))
        if result == "cold" { return print("skipped: the Tectonic cache is not primed") }
        #expect(result == "built")
    }

    @Test func cancellingABuildStopsItsWorker() async throws {
        guard available else { return }
        let dir = try project()
        defer { try? FileManager.default.removeItem(at: dir) }
        let typesetter = Typesetter(worker: Self.worker)

        let started = ContinuousClock.now
        let looping = Task { await outcome(typesetter, dir.appending(path: "doc.tex"), source: Self.loops) }
        try await Task.sleep(for: .milliseconds(500))
        looping.cancel()

        let result = await looping.value
        if result == "cold" { return print("skipped: the Tectonic cache is not primed") }
        #expect(result == "superseded")
        #expect(ContinuousClock.now - started < .seconds(30))
    }

    private func outcome(_ typesetter: Typesetter, _ entry: URL, source: String = hello) async -> String {
        do {
            _ = try await typesetter.typeset(entry: entry, source: source, onlyCached: true)
            return "built"
        } catch {
            return error.superseded ? "superseded"
                : error.timedOut ? "timed out: \(error.message)"
                : error.isColdCache ? "cold" : error.message
        }
    }

    @Test func warmupDocumentComesFromTheEngine() async throws {
        guard available else { return }
        let doc = try await Typesetter.warmupDocument(Self.worker)
        #expect(doc.hasPrefix("\\documentclass{article}"))
        #expect(doc.contains("\\maketitle"))
    }
}
