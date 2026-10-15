import Foundation
import Observation
import PDFKit
import ScribeXCore

/// A window's typesetting: the builds as you type, the preview they produce,
/// what TeX complained about, and exporting.
@Observable
final class Typesetting {

    /// `id` changes with every build, so the preview swaps documents even when
    /// the bytes happen to match.
    struct Preview {
        let id: Int
        let data: Data
        let document: PDFDocument
    }

    static let debounce = Duration.milliseconds(600)

    let engine: Engine
    @ObservationIgnored private let document: TexDocument
    /// The file on disk, once there is one. Builds run beside it so `\input`
    /// and images resolve.
    var fileURL: URL? {
        didSet { if fileURL != oldValue { loadBibliography(); scheduleBuild() } }
    }

    private(set) var preview: Preview?
    private(set) var diags: [Diagnostic] = []
    /// From reading the source, so they show without a build, and even when
    /// the build they warn about never finishes.
    private(set) var checks: [Diagnostic] = []
    private(set) var busy = false
    /// Building an export variant, which Stop does not reach: the export sheet
    /// owns that build and saves what it returns.
    private(set) var exporting = false
    /// A Fetch is downloading. Separate from `busy`, which typing sets on every
    /// pause; and a fetch runs to the end even when newer builds start.
    private(set) var fetching = false
    private(set) var missing: String?
    private(set) var absent: String?
    private(set) var ignored: Set<String> = []
    /// One line on how the last build or action went, under the preview.
    var status = "Ready"
    var autoBuild = true { didSet { if autoBuild { scheduleBuild() } } }

    @ObservationIgnored private let scratch: URL
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private var previewCount = 0
    @ObservationIgnored private var bib: (keys: [String], name: String?) = ([], nil)
    @ObservationIgnored private var pendingBuild: Task<Void, Never>?
    @ObservationIgnored private var building: Task<Void, Never>?
    @ObservationIgnored private var pendingCheck: Task<Void, Never>?
    /// CPU seconds a preview may take: several times this document's last
    /// build, so a loop is caught in seconds rather than at the full limit that
    /// Build Now allows. Nil until a build succeeds, so a long document's first
    /// build is not cut short before anything says how long it takes.
    @ObservationIgnored private var previewLimit: Int?

    init(document: TexDocument, engine: Engine) {
        self.document = document
        self.engine = engine
        scratch = engine.scratchEntry()
        let text = document.text
        pendingCheck = Task { checks = await Self.check(text) }
    }

    private var source: String { document.text }
    var visible: [Diagnostic] { (diags + checks).filter { !ignored.contains($0.key) } }

    func ignore(_ d: Diagnostic) {
        ignored.insert(d.key)
    }

    /// A file the last build needed and did not have, and the line that asked
    /// for it, for the note the editor pins there.
    struct MissingFile: Equatable {
        let file: String
        let line: Int
        /// In the TeX distribution, so Fetch can supply it; otherwise it belongs
        /// in the document's folder.
        let fetchable: Bool
    }

    var missingFile: MissingFile? {
        // Before setup every package is missing; the setup banner covers that.
        guard let file = absent ?? (engine.cache == .ready ? missing : nil) else { return nil }
        // The line that names it (\usepackage{cancel}, \includegraphics{figure.png}),
        // else where TeX stopped (a font comes from no line), else the first.
        let stem = NSRegularExpression.escapedPattern(for: (file as NSString).deletingPathExtension)
        let names = source.components(separatedBy: "\n").firstIndex {
            $0.range(of: "[{,]\\s*\(stem)[.\\w]*\\s*[,}]", options: .regularExpression) != nil
        }
        let line = names.map { $0 + 1 } ?? visible.lazy.compactMap(\.line).first ?? 1
        return MissingFile(file: file, line: line, fetchable: absent == nil)
    }

    private func loadBibliography() {
        guard let dir = fileURL?.deletingLastPathComponent() else {
            bib = ([], nil)
            return
        }
        var keys: [String] = []
        var first: String?
        for file in bibliographyFiles(source) {
            // A missing .bib is itself a build error; nothing to add here.
            guard let text = try? String(contentsOf: dir.appending(path: file), encoding: .utf8) else { continue }
            let found = bibKeys(text)
            if !found.isEmpty && first == nil { first = file }
            keys += found
        }
        bib = (keys, first)
    }

    // MARK: Building

    /// Builds never use the network, except this one when `allowNetwork` is
    /// set: "Fetch it", the user's explicit go-ahead for a missing package.
    func build(allowNetwork: Bool = false, asPreview: Bool = false) {
        pendingBuild?.cancel()
        let src = source
        building = Task { await runBuild(src, allowNetwork: allowNetwork, asPreview: asPreview) }
    }

    /// Checks wait for the same pause as a build: mid-word, a definition is
    /// often briefly one that uses itself.
    func edited() {
        pendingCheck?.cancel()
        pendingCheck = Task {
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            let found = await Self.check(source)
            if !Task.isCancelled { checks = found }
        }
        scheduleBuild()
    }

    func stop() {
        pendingBuild?.cancel()
        building?.cancel()
        // The stopped build may take a moment to end, or wait behind another
        // job first; retiring its number keeps its ticker off the status.
        seq += 1
        busy = false
        engine.clearFetched()
        status = "Stopped"
    }

    func scheduleBuild() {
        pendingBuild?.cancel()
        guard autoBuild, !engine.locked else { return }
        pendingBuild = Task {
            try? await Task.sleep(for: Self.debounce)
            if !Task.isCancelled { build(asPreview: true) }
        }
    }

    private func runBuild(_ src: String, allowNetwork: Bool, asPreview: Bool) async {
        let target = fileURL ?? scratch
        seq += 1
        let mine = seq
        busy = true
        if allowNetwork { fetching = true }
        status = allowNetwork ? "Fetching packages…" : "Typesetting…"
        // A long build shows it is still going, and how to end it.
        let ticker = allowNetwork ? nil : Task {
            let started = ContinuousClock.now
            try? await Task.sleep(for: .seconds(5))
            while !Task.isCancelled, mine == seq {
                status = "Typesetting… \(Int((ContinuousClock.now - started) / .seconds(1))) s — ⌘. to stop"
                try? await Task.sleep(for: .seconds(1))
            }
        }
        defer {
            ticker?.cancel()
            if allowNetwork { fetching = false }
            if mine == seq {
                busy = false
                engine.clearFetched()
            }
        }

        let context = LogContext(source: src, bibKeys: bib.keys, bibName: bib.name)
        let limit = asPreview ? previewLimit : nil
        do throws(BuildError) {
            let r = try await engine.typesetter.typeset(
                entry: target,
                source: src,
                onlyCached: !allowNetwork,
                // A fetch fills the shared cache, so it runs even once superseded.
                ifSuperseded: allowNetwork ? .run : .drop,
                timeLimit: limit,
                onFetch: engine.fetchHandler
            )
            // A download's time is the network's, not TeX's.
            if !allowNetwork { previewLimit = min(Typesetter.timeLimit, max(10, (r.durationMs * 5 + 999) / 1000)) }
            guard mine == seq else { return }
            let parsed = await Self.read(r.log, context: context)
            guard mine == seq else { return }
            guard let document = PDFDocument(data: r.pdf) else {
                status = "The engine produced a PDF that cannot be read"
                return
            }
            previewCount += 1
            preview = Preview(id: previewCount, data: r.pdf, document: document)
            show(parsed, missing: nil, absent: nil)
            status = "Built in \(r.durationMs) ms"
        } catch {
            // Leave the status alone: the newer build, or whoever stopped this one, owns it now.
            if error.superseded || mine != seq { return }
            if error.timedOut {
                let shortened = limit.map { $0 < Typesetter.timeLimit } ?? false
                show([Self.neverFinished(seconds: error.durationMs / 1000, shortened: shortened)], missing: nil, absent: nil)
                status = error.message
                return
            }
            if error.isColdCache {
                // Not the document's fault: point at the setup instead of listing issues.
                engine.noteColdCache()
                show([], missing: nil, absent: nil)
                status = "Waiting for the one-time download"
                return
            }
            var context = context
            context.absentFiles = Set([error.absentFile].compactMap { $0 })
            let parsed = await Self.read(error.log, context: context)
            guard mine == seq else { return }
            show(parsed, missing: error.missingFile, absent: error.absentFile)
            status = error.missingFile.map { "Missing: \($0)" }
                ?? error.absentFile.map { "Not found: \($0)" }
                ?? "Build failed"
            // Stay on the last good preview, and leave the issues panel as it
            // is: opening it here would do so on every half-typed command.
        }
    }

    private func show(_ parsed: [Diagnostic], missing: String?, absent: String?) {
        diags = parsed
        ignored = []
        self.missing = missing
        self.absent = absent
    }

    /// The worker was stopped before it wrote a log, so there is nothing to parse.
    private static func neverFinished(seconds: Int, shortened: Bool) -> Diagnostic {
        let title = "The build never finished"
        return Diagnostic(
            severity: .error,
            title: title,
            detail: "TeX was still running after \(seconds) s, so it was stopped. That usually means the "
                + "document loops forever: a command defined in terms of itself, such as "
                + "\\renewcommand{\\vec}[1]{\\vec{…}}, or a \\loop that never ends."
                + (shortened ? " If the document is only slow, Build Now (⌘R) gives it \(Typesetter.timeLimit) s." : ""),
            raw: title
        )
    }

    /// Off the main thread, like the log: it reads the whole document.
    private nonisolated static func check(_ source: String) async -> [Diagnostic] {
        sourceIssues(source)
    }

    /// Off the main thread: a long log runs to thousands of lines.
    private nonisolated static func read(
        _ log: String, context: LogContext
    ) async -> [Diagnostic] {
        parseLog(log, context: context)
    }

    // MARK: Exporting

    /// The PDF to export: the one on screen, or, when the options change the
    /// page, a build of that variant. Nil if the build fails; the status says why.
    func exportPDF(_ options: ExportOptions) async -> Data? {
        guard let shown = preview?.data else { return nil }
        guard options.needsRebuild(documentSheet: sheetOf(source)) else { return shown }
        busy = true
        exporting = true
        status = "Building for export…"
        defer {
            busy = false
            exporting = false
            engine.clearFetched()
            // Restore the preview's build output, which the export build replaced.
            build()
        }
        do throws(BuildError) {
            // Bypass `build` so the on-screen preview is not replaced by the
            // variant, and never dropped: the user asked for this one.
            seq += 1
            return try await engine.typesetter.typeset(
                entry: fileURL ?? scratch,
                source: options.apply(to: source),
                onlyCached: true,
                ifSuperseded: .run,
                onFetch: engine.fetchHandler
            ).pdf
        } catch {
            status = "Export failed: \(error.message)"
            return nil
        }
    }

    /// After the system's save panel has written the PDF to `url`.
    func exported(_ pdf: Data, to url: URL, sourceAlongside: Bool) {
        status = "Exported \(pdf.count / 1024) KB to \(url.lastPathComponent)"
        guard sourceAlongside else { return }
        let copy = url.deletingPathExtension().appendingPathExtension("tex")
        do {
            // Exported beside the document itself, its source is already there:
            // writing the buffer over it would go behind the document system's back.
            if copy.resolvingSymlinksInPath() != fileURL?.resolvingSymlinksInPath() {
                // The save panel asked about replacing the PDF only, so any
                // other .tex of that name is not ours to replace.
                try Data(source.utf8).write(to: copy, options: .withoutOverwriting)
            }
            status += " (with source)"
        } catch CocoaError.fileWriteFileExists {
            status = "Exported the PDF, but not the source: \(copy.lastPathComponent) is already there"
        } catch {
            status = "Exported the PDF, but not the source: \(error.localizedDescription)"
        }
    }
}

extension Typesetting {
    /// Issues to show in a preview, where nothing is typeset.
    func showForPreview(_ issues: [Diagnostic]) {
        diags = issues
    }
}
