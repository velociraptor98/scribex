import AppKit
import Observation
import PDFKit
import ScribeXCore
import SwiftUI

/// One document window: its builds, preview, issues and panels. The file
/// itself, saving and the edited state belong to the document system.
@Observable
public final class Session {
    public enum RightPane { case proof, marks }

    public enum Zoom: Equatable {
        case fit
        case scale(Double)
    }

    /// `id` changes with every build, so the preview swaps documents even when
    /// the bytes happen to match.
    struct Preview {
        let id: Int
        let data: Data
        let document: PDFDocument
    }

    static let debounce = Duration.milliseconds(600)
    static let minZoom = 0.25
    static let maxZoom = 4.0
    static let zoomSteps = [0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4]

    let engine: Engine
    @ObservationIgnored let document: TexDocument
    /// The file on disk, once there is one. Builds run beside it so `\input`
    /// and images resolve.
    var fileURL: URL? {
        didSet { if fileURL != oldValue { loadBibliography(); scheduleBuild() } }
    }

    private(set) var preview: Preview?
    private(set) var diags: [Diagnostic] = []
    private(set) var press: [PressRow] = []
    private(set) var busy = false
    private(set) var missing: String?
    private(set) var absent: String?
    private(set) var buildMs: Int?
    private(set) var sections: [OutlineEntry] = []
    private(set) var tally = DocStats(sections: 0, equations: 0, citations: 0)
    private(set) var ignored: Set<String> = []
    var status = "Ready"
    var autoBuild = true { didSet { if autoBuild { scheduleBuild() } } }
    var zoom = Zoom.fit
    /// What "fit" resolves to on screen; zooming steps from here.
    var scale = 1.0
    var rightPane = RightPane.proof
    var pressOpen = false
    var paletteOpen = false
    var exportOpen = false
    var selection = ""

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

    var source: String { document.text }
    var name: String { fileURL?.lastPathComponent ?? "untitled.tex" }
    var visible: [Diagnostic] { diags.filter { !ignored.contains($0.key) } }

    // Shared state, reached through the session so views need only one model.
    var offline: Bool { engine.offline }
    var fetched: [String] { engine.fetched }
    func toggleOffline() { engine.toggleOffline() }
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

    /// The scale on screen may be an odd fit-width value between stops.
    func zoom(by direction: Int) {
        let next = direction > 0
            ? Self.zoomSteps.first { $0 > scale + 0.005 }
            : Self.zoomSteps.last { $0 < scale - 0.005 }
        zoom = .scale(next ?? (direction > 0 ? Self.maxZoom : Self.minZoom))
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

    /// `allowNetwork` overrides the offline switch for this one build, for
    /// "fetch it".
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
        let name = self.name
        do throws(BuildError) {
            let r = try await engine.typesetter.typeset(
                entry: target,
                source: src,
                onlyCached: allowNetwork ? false : engine.offline,
                // Only the explicit per-build override counts as a fetch the user
                // asked for. Leaving the offline switch off does not, or every
                // keystroke would queue an undroppable build.
                ifSuperseded: allowNetwork ? .run : .drop,
                onFetch: engine.fetchHandler
            )
            guard mine == seq else { return }
            let (parsed, rows) = await Self.read(r.log, context: context, name: name)
            guard mine == seq else { return }
            guard let document = PDFDocument(data: r.pdf) else {
                status = "The engine produced a PDF that cannot be read"
                return
            }
            previewCount += 1
            preview = Preview(id: previewCount, data: r.pdf, document: document)
            show(parsed, rows, missing: nil, absent: nil, ms: r.durationMs)
            status = "Built in \(r.durationMs) ms"
        } catch {
            // Leave the status alone: the newer build owns it now.
            if error.superseded || mine != seq { return }
            if error.isColdCache {
                // Not the document's fault: point at the setup instead of listing issues.
                engine.noteColdCache()
                show([], [], missing: nil, absent: nil, ms: error.durationMs)
                status = "Waiting for the one-time download"
                return
            }
            var context = context
            context.absentFiles = Set([error.absentFile].compactMap { $0 })
            let (parsed, rows) = await Self.read(error.log, context: context, name: name)
            guard mine == seq else { return }
            show(parsed, rows, missing: error.missingFile, absent: error.absentFile, ms: error.durationMs)
            status = error.missingFile.map { "Missing: \($0)" }
                ?? error.absentFile.map { "Not found: \($0)" }
                ?? "Build failed"
            // Stay on the last good preview. Switching to Issues here would do
            // it on every half-typed command while building as you type.
        }
    }

    private func show(_ parsed: [Diagnostic], _ rows: [PressRow], missing: String?, absent: String?, ms: Int) {
        diags = parsed
        press = rows
        ignored = []
        self.missing = missing
        self.absent = absent
        buildMs = ms
    }

    /// Off the main thread: a long log runs to thousands of lines.
    private nonisolated static func read(
        _ log: String, context: LogContext, name: String
    ) async -> ([Diagnostic], [PressRow]) {
        let parsed = parseLog(log, context: context)
        return (parsed, pressLog(log, source: context.source, name: name, diags: parsed))
    }

    // MARK: Exporting

    func requestExport() {
        if preview != nil {
            exportOpen = true
        } else {
            status = "Nothing to export yet"
        }
    }

    func export(_ options: ExportOptions) {
        // The PDF on screen, kept now: a newer build may replace it while the
        // save panel is open.
        guard let shown = preview?.data else { return }
        let target = fileURL ?? scratch
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (name as NSString).deletingPathExtension + ".pdf"
        exportOpen = false
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
                        onlyCached: engine.offline,
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
    /// The last document window to appear, for the debug script.
    static weak var active: Session?

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

extension FocusedValues {
    /// The session of the frontmost document window, for the menu bar.
    @Entry public var session: Session?
}
