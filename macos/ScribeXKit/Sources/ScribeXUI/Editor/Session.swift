import AppKit
import Observation
import PDFKit
import ScribeXCore
import SwiftUI

/// One document window's document: its builds, preview and issues. The file
/// itself, saving and the edited state belong to the document system; what
/// the window shows (panels, sheets, zoom) belongs to its views.
@Observable
public final class Session {

    /// `id` changes with every build, so the preview swaps documents even when
    /// the bytes happen to match.
    struct Preview {
        let id: Int
        let data: Data
        let document: PDFDocument
    }

    static let debounce = Duration.milliseconds(600)

    let engine: Engine
    @ObservationIgnored let document: TexDocument
    /// The file on disk, once there is one. Builds run beside it so `\input`
    /// and images resolve.
    var fileURL: URL? {
        didSet { if fileURL != oldValue { loadBibliography(); scheduleBuild() } }
    }

    private(set) var preview: Preview?
    private(set) var diags: [Diagnostic] = []
    private(set) var busy = false
    private(set) var missing: String?
    private(set) var absent: String?
    private(set) var buildMs: Int?
    private(set) var sections: [OutlineEntry] = []
    private(set) var tally = DocStats(sections: 0, equations: 0, citations: 0)
    private(set) var ignored: Set<String> = []
    var status = "Ready"
    var autoBuild = true { didSet { if autoBuild { scheduleBuild() } } }

    public let editor = EditorHandle()
    @ObservationIgnored private let scratch: URL
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private var previewCount = 0
    @ObservationIgnored private var bib: (keys: [String], name: String?) = ([], nil)
    @ObservationIgnored private var pendingBuild: Task<Void, Never>?
    @ObservationIgnored private var pendingDerive: Task<Void, Never>?

    public init(document: TexDocument, engine: Engine) {
        self.document = document
        self.engine = engine
        scratch = engine.scratchEntry()
        derive()
    }

    /// A file the last build needed and did not have, and the line that asked
    /// for it, for the note the editor pins there.
    struct LineNote: Equatable {
        let file: String
        let line: Int
        /// In the TeX distribution, so Fetch can supply it; otherwise it belongs
        /// in the document's folder.
        let fetchable: Bool
    }

    var lineNote: LineNote? {
        // Before setup every package is missing; the setup banner covers that.
        guard let file = absent ?? (engine.cache == .ready ? missing : nil) else { return nil }
        // The line that names it (\usepackage{cancel}, \includegraphics{figure.png}),
        // else where TeX stopped (a font comes from no line), else the first.
        let stem = NSRegularExpression.escapedPattern(for: (file as NSString).deletingPathExtension)
        let names = source.components(separatedBy: "\n").firstIndex {
            $0.range(of: "[{,]\\s*\(stem)[.\\w]*\\s*[,}]", options: .regularExpression) != nil
        }
        let line = names.map { $0 + 1 } ?? visible.lazy.compactMap(\.line).first ?? 1
        return LineNote(file: file, line: line, fetchable: absent == nil)
    }

    var source: String { document.text }
    var name: String { fileURL?.lastPathComponent ?? "untitled.tex" }
    var visible: [Diagnostic] { diags.filter { !ignored.contains($0.key) } }

    // Shared state, reached through the session so views need only one model.
    var fetched: [String] { engine.fetched }
    func setUp() { engine.setUp() }

    // MARK: Editing

    /// The editor owns the text while the user types and reports each change.
    func edit(_ text: String) {
        document.text = text
        scheduleDerive()
        scheduleBuild()
    }

    func insert(_ text: String) {
        // "Turn the selection into a table" is the one suggestion whose output
        // depends on what is selected, so it is built here rather than in the
        // catalogue.
        let selection = editor.selectedText
        if text.isEmpty && !selection.isEmpty {
            guard let table = selectionToTable(selection) else {
                status = "That selection is not rows of separated values"
                return
            }
            editor.insert(table)
            return
        }
        editor.insert(text)
    }

    func applyFix(_ fix: Fix) {
        editor.replaceOnLine(fix.line, find: fix.find, replace: fix.replace)
        status = fix.label
    }

    func ignore(_ d: Diagnostic) {
        ignored.insert(d.key)
    }

    func revealFolder() {
        guard let fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func scheduleDerive() {
        pendingDerive?.cancel()
        pendingDerive = Task {
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled { derive() }
        }
    }

    private func derive() {
        sections = outline(source)
        tally = stats(source)
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
        status = allowNetwork ? "Fetching packages…" : "Typesetting…"
        defer {
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
            show(parsed, missing: nil, absent: nil, ms: r.durationMs)
            status = "Built in \(r.durationMs) ms"
        } catch {
            // Leave the status alone: the newer build owns it now.
            if error.superseded || mine != seq { return }
            if error.isColdCache {
                // Not the document's fault: point at the setup instead of listing issues.
                engine.noteColdCache()
                show([], missing: nil, absent: nil, ms: error.durationMs)
                status = "Waiting for the one-time download"
                return
            }
            var context = context
            context.absentFiles = Set([error.absentFile].compactMap { $0 })
            let parsed = await Self.read(error.log, context: context)
            guard mine == seq else { return }
            show(parsed, missing: error.missingFile, absent: error.absentFile, ms: error.durationMs)
            status = error.missingFile.map { "Missing: \($0)" }
                ?? error.absentFile.map { "Not found: \($0)" }
                ?? "Build failed"
            // Stay on the last good preview, and leave the issues panel as it
            // is: opening it here would do so on every half-typed command.
        }
    }

    private func show(_ parsed: [Diagnostic], missing: String?, absent: String?, ms: Int) {
        diags = parsed
        ignored = []
        self.missing = missing
        self.absent = absent
        buildMs = ms
    }

    /// Off the main thread: a long log runs to thousands of lines.
    private nonisolated static func read(
        _ log: String, context: LogContext
    ) async -> [Diagnostic] {
        parseLog(log, context: context)
    }

    // MARK: Exporting

    func export(_ options: ExportOptions) {
        // The PDF on screen, kept now: a newer build may replace it while the
        // save panel is open.
        guard let shown = preview?.data else { return }
        let target = fileURL ?? scratch
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (name as NSString).deletingPathExtension + ".pdf"
        Task {
            let response = if let window = NSApp.keyWindow {
                await panel.beginSheetModal(for: window)
            } else {
                panel.runModal()
            }
            guard response == .OK, let dest = panel.url else { return }
            let rebuild = options.needsRebuild(documentSheet: sheetOf(source))
            busy = true
            defer {
                busy = false
                engine.clearFetched()
                // Restore the preview's build output, which the export build replaced.
                if rebuild { build() }
            }
            do {
                var pdf = shown
                if rebuild {
                    status = "Building for export…"
                    // Bypass `build` so the on-screen preview is not replaced by
                    // the variant, and never dropped: the user asked for this one.
                    seq += 1
                    let variant = try await engine.typesetter.typeset(
                        entry: target,
                        source: options.apply(to: source),
                        onlyCached: true,
                        ifSuperseded: .run,
                        onFetch: engine.fetchHandler
                    )
                    pdf = variant.pdf
                }
                try pdf.write(to: dest)
                if options.sourceAlongside {
                    try Data(source.utf8).write(to: dest.deletingPathExtension().appendingPathExtension("tex"))
                }
                status = "Exported \(pdf.count / 1024) KB to \(dest.lastPathComponent)"
                    + (options.sourceAlongside ? " (with source)" : "")
            } catch let error as BuildError {
                status = "Export failed: \(error.message)"
            } catch {
                status = "Export failed: \(error)"
            }
        }
    }
}

#if DEBUG
extension Session {
    /// A window's worth of state for previews: the article template, and any
    /// issues to show. Nothing is typeset.
    static func preview(issues: [Diagnostic] = []) -> Session {
        let session = Session(document: TexDocument(), engine: .preview)
        session.diags = issues
        return session
    }
}

extension Engine {
    static let preview = Engine(worker: URL(filePath: "/usr/bin/false"))
}
#endif

