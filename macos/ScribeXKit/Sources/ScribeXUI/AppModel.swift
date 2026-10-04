import AppKit
import Observation
import PDFKit
import ScribeXCore
import UniformTypeIdentifiers

/// App state, builds, file handling. What App.tsx did, minus the rendering.
@Observable
public final class AppModel {
    public enum Screen { case welcome, editor }
    public enum RightPane { case proof, marks }
    public enum CacheState { case unknown, cold, downloading, failed, ready }
    public enum Autosaving { case idle, saving, saved }

    /// A fixed scale, or whatever makes the widest page fill the pane.
    public enum Zoom: Equatable {
        case fit
        case scale(Double)
    }

    public struct SetupProgress {
        /// Resources downloaded so far in this run.
        var files = 0
        /// The one arriving now.
        var current: String?
        var error: String?
    }

    /// A built PDF on screen. `id` changes with every build, so the preview
    /// knows to swap documents even when the bytes happen to match.
    public struct Preview {
        let id: Int
        let data: Data
        let document: PDFDocument
    }

    static let debounce = Duration.milliseconds(600)
    /// How often unsaved edits are written back to the document's file.
    static let autosaveEvery = Duration.seconds(10)
    /// How long the autosave indicator lingers. A save takes a few milliseconds,
    /// far too quick to see without holding it on screen.
    static let savingShown = Duration.milliseconds(700)
    static let savedShown = Duration.seconds(2)

    static let minZoom = 0.25
    static let maxZoom = 4.0
    static let zoomSteps = [0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4]

    // MARK: state

    var screen = Screen.welcome
    /// The editor's text. The editor owns it while the user types and reports
    /// each change through `edit(_:)`.
    private(set) var source = articleSource
    private(set) var path: URL?
    private(set) var preview: Preview?
    private(set) var diags: [Diagnostic] = []
    private(set) var press: [PressRow] = []
    var status = "Ready"
    private(set) var busy = false
    private(set) var offline = true
    private(set) var missing: String?
    var zoom = Zoom.fit
    /// The scale on screen, which "fit" resolves to; zooming steps from here.
    var scale = 1.0
    var autoBuild = true { didSet { if autoBuild { scheduleBuild() } } }
    var autoSave = true { didSet { scheduleAutosave() } }
    private(set) var autosaving = Autosaving.idle
    private(set) var cache = CacheState.unknown
    private(set) var setup = SetupProgress()
    /// Resources the engine has downloaded during the build in progress.
    private(set) var fetched: [String] = []
    private(set) var dirty = false
    private(set) var buildMs: Int?
    private(set) var recent: [RecentDoc]
    var rightPane = RightPane.proof
    var pages = 0
    var page = 1
    var pressOpen = false
    var paletteOpen = false
    var exportOpen = false
    /// The editor's selected text, so the palette can offer selection-aware actions.
    var selection = ""
    /// Issues the reader has ignored; cleared on every new build.
    private(set) var ignored: Set<String> = []
    private var bib: (keys: [String], name: String?) = ([], nil)

    /// Derived from `source`, a beat after typing stops.
    private(set) var sections: [OutlineEntry] = []
    private(set) var tally = DocStats(sections: 0, equations: 0, citations: 0)

    // MARK: plumbing

    public let editor = EditorHandle()
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private let typesetter: Typesetter
    @ObservationIgnored private let recentStore = RecentStore()
    @ObservationIgnored private let dataDirectory: URL
    /// Builds into here until the user opens or saves a real document.
    @ObservationIgnored private let scratch: URL
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private var previewCount = 0
    @ObservationIgnored private var settingUp = false
    @ObservationIgnored private var pendingBuild: Task<Void, Never>?
    @ObservationIgnored private var pendingDerive: Task<Void, Never>?
    @ObservationIgnored private var autosaveLoop: Task<Void, Never>?
    @ObservationIgnored private var autosaveShown: Task<Void, Never>?

    /// `worker` is the `scribex-typeset` executable.
    public init(worker: URL) {
        typesetter = Typesetter(worker: worker)
        recent = recentStore.load()
        // Where the Tauri app kept its scratch file and setup marker, so a
        // machine that ran it does not download the essentials twice.
        dataDirectory = URL.applicationSupportDirectory.appending(path: "com.kunalsingh.scribex", directoryHint: .isDirectory)
        scratch = dataDirectory.appending(path: "scratch.tex")
        cache = Typesetter.cacheReady(in: dataDirectory) ? .ready : .cold
        derive()
    }

    var name: String { path?.lastPathComponent ?? "untitled.tex" }
    var visible: [Diagnostic] { diags.filter { !ignored.contains($0.key) } }
    /// No document opens until the first-run download has finished.
    var locked: Bool { cache != .ready }

    // MARK: building

    /// Typeset `source` now. `allowNetwork` overrides the offline switch for
    /// this one build, for "fetch it".
    func build(allowNetwork: Bool = false) {
        pendingBuild?.cancel()
        let src = source
        Task { await runBuild(src, allowNetwork: allowNetwork) }
    }

    /// Debounced live rebuild, once a document is on screen.
    private func scheduleBuild() {
        pendingBuild?.cancel()
        guard screen == .editor, autoBuild else { return }
        pendingBuild = Task {
            try? await Task.sleep(for: Self.debounce)
            if !Task.isCancelled { build() }
        }
    }

    private func runBuild(_ src: String, allowNetwork: Bool) async {
        let target = path ?? scratch
        seq += 1
        let mine = seq
        busy = true
        fetched = []
        status = allowNetwork ? "Fetching packages…" : "Typesetting…"
        defer {
            if mine == seq {
                busy = false
                fetched = []
            }
        }

        let context = LogContext(source: src, bibKeys: bib.keys, bibName: bib.name)
        let name = self.name
        do throws(BuildError) {
            let r = try await typesetter.typeset(
                entry: target,
                source: src,
                onlyCached: allowNetwork ? false : offline,
                // Only the explicit per-build override counts as a fetch the user
                // asked for. Leaving the offline switch off does not, or every
                // keystroke would queue an undroppable build.
                ifSuperseded: allowNetwork ? .run : .drop,
                onFetch: fetchHandler
            )
            guard mine == seq else { return }  // a newer build superseded this one
            let (parsed, rows) = await Self.read(r.log, context: context, name: name)
            guard mine == seq else { return }
            guard let document = PDFDocument(data: r.pdf) else {
                status = "The engine produced a PDF that cannot be read"
                return
            }
            previewCount += 1
            preview = Preview(id: previewCount, data: r.pdf, document: document)
            diags = parsed
            press = rows
            ignored = []
            missing = nil
            buildMs = r.durationMs
            status = "Built in \(r.durationMs) ms"
        } catch {
            // The typesetter runs one job at a time and drops those a newer
            // request has overtaken. Leave the status alone — the newer build
            // owns it now.
            if error.superseded || mine != seq { return }
            if error.isColdCache {
                // Not the document's fault: point at the setup instead of listing
                // issues. Also catches a cache cleared since setup ran.
                if cache != .downloading && cache != .failed { cache = .cold }
                diags = []
                press = []
                missing = nil
                buildMs = error.durationMs
                status = "Waiting for the one-time download"
                return
            }
            let (parsed, rows) = await Self.read(error.log, context: context, name: name)
            guard mine == seq else { return }
            diags = parsed
            press = rows
            ignored = []
            missing = error.missingFile
            buildMs = error.durationMs
            status = error.missingFile.map { "Missing: \($0)" } ?? "Build failed"
            // Stay on the last good preview. Switching to Issues here would do
            // it on every half-typed command while building as you type.
        }
    }

    /// Parse a log off the main thread; a long one runs to thousands of lines.
    private nonisolated static func read(
        _ log: String, context: LogContext, name: String
    ) async -> ([Diagnostic], [PressRow]) {
        let parsed = parseLog(log, context: context)
        return (parsed, pressLog(log, source: context.source, name: name, diags: parsed))
    }

    /// Each package or font the engine downloads, from any build or setup run.
    private var fetchHandler: @Sendable (String) -> Void {
        { [weak self] name in
            Task { @MainActor in self?.noteFetch(name) }
        }
    }

    private func noteFetch(_ name: String) {
        guard busy || settingUp else { return }
        fetched.append(name)
        status = "Downloading \(name)…"
        if settingUp {
            setup.files += 1
            setup.current = name
        }
    }

    /// The first-run download of everything the warmup set and plates use. See
    /// docs/OFFLINE.md. Not `busy`: builds queue behind it and then succeed from
    /// the fresh cache.
    func setUp() {
        guard !settingUp else { return }
        settingUp = true
        cache = .downloading
        setup = SetupProgress()
        status = "Downloading the LaTeX essentials…"
        Task {
            defer {
                settingUp = false
                fetched = []
            }
            do throws(BuildError) {
                let ms = try await typesetter.warmUp(
                    documents: plates.map(\.source),
                    dataDirectory: dataDirectory,
                    onFetch: fetchHandler
                )
                cache = .ready
                missing = nil
                status = "Ready in \(Int((Double(ms) / 1000).rounded())) s — ScribeX now works offline"
                // The download is long enough for the reader to have opened
                // something meanwhile; build whatever is on screen now.
                if screen == .editor { build() }
            } catch {
                // Priming is never dropped as superseded, so anything caught here is real.
                cache = .failed
                setup.error = error.message
                status = "The download stopped"
            }
        }
    }

    func toggleOffline() {
        offline.toggle()
    }

    // MARK: documents

    /// Show `text` in the editor, as the document at `url` (nil for untitled).
    func adopt(_ text: String, url: URL?, note: String) {
        guard !locked else { return }
        // Write back edits the autosave timer has not reached yet; the buffer is
        // about to be replaced.
        flushAutosave()
        source = text
        path = url
        editor.load(text)
        diags = []
        press = []
        ignored = []
        missing = nil
        dirty = false
        preview = nil
        pages = 0
        page = 1
        rightPane = .proof
        screen = .editor
        status = note
        derive()
        loadBibliography()
        if let url { remember(text, at: url) }
        scheduleAutosave()
        scheduleBuild()
    }

    func newDocument() {
        adopt(articleSource, url: nil, note: "New document")
    }

    func openPlate(_ plate: Plate) {
        adopt(plate.source, url: nil, note: "\(plate.name) plate")
    }

    func openFile() {
        guard !locked else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.texType]
        Task {
            guard await run(panel) == .OK, let url = panel.url else { return }
            open(url)
        }
    }

    func openRecent(_ doc: RecentDoc) {
        let url = URL(filePath: doc.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            status = "\(url.lastPathComponent) has moved or been deleted"
            return
        }
        open(url)
    }

    private func open(_ url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            adopt(text, url: url, note: "Opened \(url.lastPathComponent)")
        } catch {
            status = "Cannot open \(url.lastPathComponent): it is not UTF-8 text"
        }
    }

    /// A keystroke, paste or fix in the editor.
    func edit(_ text: String) {
        source = text
        dirty = true
        scheduleDerive()
        scheduleBuild()
    }

    /// Write the buffer to disk, prompting for a location if there isn't one yet.
    func save(as forceDialog: Bool = false) {
        Task { await saveFile(forceDialog: forceDialog) }
    }

    @discardableResult
    func saveFile(forceDialog: Bool = false) async -> Bool {
        var target = path
        if target == nil || forceDialog {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [Self.texType]
            panel.nameFieldStringValue = path?.lastPathComponent ?? "untitled.tex"
            panel.directoryURL = path?.deletingLastPathComponent()
            guard await run(panel) == .OK, let url = panel.url else { return false }
            target = url
        }
        guard let target else { return false }
        do {
            try saveDocument(source, to: target)
            // Adopting the new path also moves where future builds are rooted.
            if target != path {
                path = target
                loadBibliography()
                scheduleAutosave()
                scheduleBuild()
            }
            dirty = false
            status = "Saved \(target.lastPathComponent)"
            remember(source, at: target)
            return true
        } catch {
            status = "Save failed: \(error)"
            return false
        }
    }

    private func remember(_ text: String, at url: URL) {
        recent = recentStore.remember(RecentDoc(
            path: url.path,
            title: documentTitle(text, path: url.path),
            sections: outline(text).count,
            citations: stats(text).citations
        ))
    }

    /// Bibliography keys, so an undefined citation can propose the right one.
    private func loadBibliography() {
        guard let dir = path?.deletingLastPathComponent() else {
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

    // MARK: autosave

    /// Autosave on a fixed beat rather than after a pause, so a long stretch of
    /// continuous typing is still written back. Ticks with nothing new are no-ops.
    private func scheduleAutosave() {
        autosaveLoop?.cancel()
        guard autoSave, path != nil else { return }
        autosaveLoop = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.autosaveEvery)
                if !Task.isCancelled { flushAutosave() }
            }
        }
    }

    /// Autosave now whatever is waiting on the timer. Only a document that
    /// already has a file autosaves; an untitled one needs ⌘S to choose where
    /// it goes.
    func flushAutosave() {
        guard autoSave, dirty, let path else { return }
        autosaveShown?.cancel()
        autosaving = .saving
        do {
            try saveDocument(source, to: path)
            dirty = false
            autosaveShown = Task {
                try? await Task.sleep(for: Self.savingShown)
                guard !Task.isCancelled else { return }
                autosaving = .saved
                try? await Task.sleep(for: Self.savedShown)
                guard !Task.isCancelled else { return }
                autosaving = .idle
            }
        } catch {
            autosaving = .idle
            status = "Autosave failed: \(error)"
        }
    }

    // MARK: export

    func requestExport() {
        guard screen == .editor else { return }
        if preview != nil {
            exportOpen = true
        } else {
            status = "Nothing to export yet"
        }
    }

    /// Export honouring the export sheet. Options that change the document are
    /// applied to a throwaway build; the buffer and the file are left alone.
    func export(_ options: ExportOptions) {
        let target = path ?? scratch
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (name as NSString).deletingPathExtension + ".pdf"
        exportOpen = false
        Task {
            guard await run(panel) == .OK, let dest = panel.url else { return }
            let rebuild = options.needsRebuild(documentSheet: sheetOf(source))
            busy = true
            defer {
                busy = false
                fetched = []
                // Restore the preview's build output, which the export build replaced.
                if rebuild { build() }
            }
            do {
                let bytes: Int
                if rebuild {
                    status = "Building for export…"
                    // Bypass `build` so the on-screen preview is not replaced by
                    // the variant, and never dropped: the user asked for this one.
                    seq += 1
                    let variant = try await typesetter.typeset(
                        entry: target,
                        source: options.apply(to: source),
                        onlyCached: offline,
                        ifSuperseded: .run,
                        onFetch: fetchHandler
                    )
                    // Written from the bytes the build returned, not copied from
                    // the build directory, where a queued preview may land first.
                    try variant.pdf.write(to: dest)
                    bytes = variant.pdf.count
                } else {
                    bytes = try exportPDF(for: target, to: dest)
                }
                if options.sourceAlongside {
                    try saveDocument(source, to: dest.deletingPathExtension().appendingPathExtension("tex"))
                }
                status = "Exported \(bytes / 1024) KB to \(dest.lastPathComponent)"
                    + (options.sourceAlongside ? " (with source)" : "")
            } catch let error as BuildError {
                status = "Export failed: \(error.message)"
            } catch {
                status = "Export failed: \(error)"
            }
        }
    }

    // MARK: editing

    func applyFix(_ fix: Fix) {
        editor.replaceOnLine(fix.line, find: fix.find, replace: fix.replace)
        status = fix.label
    }

    func ignore(_ d: Diagnostic) {
        ignored.insert(d.key)
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

    // MARK: zoom

    /// The next stop up or down from the scale on screen, which may be an odd
    /// fit-width value.
    func zoom(by direction: Int) {
        let next = direction > 0
            ? Self.zoomSteps.first { $0 > scale + 0.005 }
            : Self.zoomSteps.last { $0 < scale - 0.005 }
        zoom = .scale(next ?? (direction > 0 ? Self.maxZoom : Self.minZoom))
    }

    // MARK: closing

    /// Confirm before discarding unsaved work. Autosaving documents are written
    /// back first, so the question only comes up if that fails or the document
    /// has no file yet. Calls `proceed` with whether to go ahead.
    func confirmDiscard(_ proceed: @escaping (Bool) -> Void) {
        flushAutosave()
        guard dirty, let window else { return proceed(true) }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Close without saving?"
        alert.informativeText = "\u{201C}\(name)\u{201D} has unsaved changes. They will be lost."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { proceed($0 == .alertFirstButtonReturn) }
    }

    // MARK: helpers

    static let texType = UTType(filenameExtension: "tex", conformingTo: .plainText) ?? .plainText

    /// Show a panel as a sheet on the window, or on its own without one.
    private func run(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
        if let window { return await panel.beginSheetModal(for: window) }
        return panel.runModal()
    }
}
