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
    private(set) var busy = false
    /// A Fetch is downloading. Separate from `busy`, which typing sets on every
    /// pause; and a fetch runs to the end even when newer builds start.
    private(set) var fetching = false
    private var missingNote: MissingFile?
    private(set) var ignored: Set<String> = []
    /// One line on how the last build or action went, under the preview.
    var status = "Ready"
    var autoBuild = true { didSet { if autoBuild { scheduleBuild() } } }

    @ObservationIgnored private let scratch: URL
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private var previewCount = 0
    @ObservationIgnored private var bib: (keys: [String], name: String?) = ([], nil)
    @ObservationIgnored private var pendingBuild: Task<Void, Never>?

    init(document: TexDocument, engine: Engine) {
        self.document = document
        self.engine = engine
        scratch = engine.scratchEntry()
    }

    private var source: String { document.text }
    var visible: [Diagnostic] { diags.filter { !ignored.contains($0.key) } }

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
        missingNote?.fetchable == false || engine.cache == .ready ? missingNote : nil
    }

    /// Found once per build rather than on every redraw that reads it.
    private static func note(
        missing: String?, absent: String?, in source: String, issues: [Diagnostic]
    ) -> MissingFile? {
        guard let file = absent ?? missing else { return nil }
        // The line that names it (\usepackage{cancel}, \includegraphics{figure.png}),
        // else where TeX stopped (a font comes from no line), else the first.
        let stem = NSRegularExpression.escapedPattern(for: (file as NSString).deletingPathExtension)
        let names = source.components(separatedBy: "\n").firstIndex {
            $0.range(of: "[{,]\\s*\(stem)[.\\w]*\\s*[,}]", options: .regularExpression) != nil
        }
        let line = names.map { $0 + 1 } ?? issues.lazy.compactMap(\.line).first ?? 1
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
    func build(allowNetwork: Bool = false) {
        pendingBuild?.cancel()
        let src = source
        Task { await runBuild(src, allowNetwork: allowNetwork) }
    }

    func scheduleBuild() {
        pendingBuild?.cancel()
        guard autoBuild, !engine.locked else { return }
        pendingBuild = Task {
            try? await Task.sleep(for: Self.debounce)
            if !Task.isCancelled { build() }
        }
    }

    private func runBuild(_ src: String, allowNetwork: Bool) async {
        let target = fileURL ?? scratch
        seq += 1
        let mine = seq
        busy = true
        if allowNetwork { fetching = true }
        status = allowNetwork ? "Fetching packages…" : "Typesetting…"
        defer {
            if allowNetwork { fetching = false }
            if mine == seq {
                busy = false
                engine.clearFetched()
            }
        }

        let context = LogContext(source: src, bibKeys: bib.keys, bibName: bib.name)
        do throws(BuildError) {
            let r = try await engine.typesetter.typeset(
                entry: target,
                source: src,
                onlyCached: !allowNetwork,
                // A fetch fills the shared cache, so it runs even once superseded.
                ifSuperseded: allowNetwork ? .run : .drop,
                onFetch: engine.fetchHandler
            )
            guard mine == seq else { return }
            let parsed = await Self.read(r.log, context: context)
            guard mine == seq else { return }
            guard let document = PDFDocument(data: r.pdf) else {
                status = "The engine produced a PDF that cannot be read"
                return
            }
            previewCount += 1
            preview = Preview(id: previewCount, data: r.pdf, document: document)
            show(parsed, missing: nil, absent: nil, in: src)
            status = "Built in \(r.durationMs) ms"
        } catch {
            // Leave the status alone: the newer build owns it now.
            if error.superseded || mine != seq { return }
            if error.isColdCache {
                // Not the document's fault: point at the setup instead of listing issues.
                engine.noteColdCache()
                show([], missing: nil, absent: nil, in: src)
                status = "Waiting for the one-time download"
                return
            }
            var context = context
            context.absentFiles = Set([error.absentFile].compactMap { $0 })
            let parsed = await Self.read(error.log, context: context)
            guard mine == seq else { return }
            show(parsed, missing: error.missingFile, absent: error.absentFile, in: src)
            status = error.missingFile.map { "Missing: \($0)" }
                ?? error.absentFile.map { "Not found: \($0)" }
                ?? "Build failed"
            // Stay on the last good preview, and leave the issues panel as it
            // is: opening it here would do so on every half-typed command.
        }
    }

    private func show(_ parsed: [Diagnostic], missing: String?, absent: String?, in src: String) {
        diags = parsed
        ignored = []
        missingNote = Self.note(missing: missing, absent: absent, in: src, issues: parsed)
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
        status = "Building for export…"
        defer {
            busy = false
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
