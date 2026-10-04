import AppKit
import ScribeXCore
import SwiftUI

/// The window is AppKit's so that closing it, by the close button or ⌘Q, can
/// wait on unsaved work. SwiftUI scenes offer no such hook.
public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public let model: AppModel
    private var window: NSWindow?
    /// The user agreed to lose unsaved work, so the next close goes through.
    private var closing = false

    public override init() {
        model = AppModel(worker: Self.worker)
        super.init()
    }

    /// SCRIBEX_WORKER points at a worker outside a bundle, for development.
    private static var worker: URL {
        if let path = ProcessInfo.processInfo.environment["SCRIBEX_WORKER"] {
            return URL(filePath: path)
        }
        return Bundle.main.url(forAuxiliaryExecutable: "scribex-typeset")
            ?? Bundle.main.bundleURL.appending(path: "Contents/MacOS/scribex-typeset")
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // The design is dark only.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ScribeX"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Ink.ground
        window.minSize = NSSize(width: 880, height: 560)
        let host = NSHostingView(rootView: RootView().environment(model))
        // The window keeps its own size; by default the hosting view would
        // resize it to whatever SwiftUI considers ideal.
        host.sizingOptions = []
        window.contentView = host
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("ScribeX")
        window.makeKeyAndOrderFront(nil)
        self.window = window
        model.window = window
        #if DEBUG
        DebugScript.runIfRequested(model: model, window: window)
        #endif
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closing { return true }
        model.confirmDiscard { [weak self, weak sender] discard in
            guard discard else { return }
            self?.closing = true
            sender?.close()
        }
        return false
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !closing, window?.isVisible == true else { return .terminateNow }
        model.confirmDiscard { [weak self] discard in
            self?.closing = discard
            sender.reply(toApplicationShouldTerminate: discard)
        }
        return .terminateLater
    }
}

public struct AppCommands: Commands {
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    private var editing: Bool { model.screen == .editor }

    public var body: some Commands {
        CommandGroup(replacing: .appSettings) {}

        CommandGroup(replacing: .newItem) {
            Button("New Document", action: model.newDocument)
                .keyboardShortcut("n")
                .disabled(model.locked)
            Button("Open…", action: model.openFile)
                .keyboardShortcut("o")
                .disabled(model.locked)
            Menu("Open Recent") {
                ForEach(model.recent) { doc in
                    Button(doc.title) { model.openRecent(doc) }
                }
            }
            .disabled(model.locked || model.recent.isEmpty)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { model.save() }
                .keyboardShortcut("s")
                .disabled(!editing)
            Button("Save As…") { model.save(as: true) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!editing)
            Divider()
            Button("Export as PDF…", action: model.requestExport)
                .keyboardShortcut("e")
                .disabled(!editing)
        }

        CommandGroup(replacing: .printItem) {}

        CommandMenu("Format") {
            Button("Bold") { model.insert("\\textbf{\(caret)}") }
                .keyboardShortcut("b")
                .disabled(!editing)
            Button("Italic") { model.insert("\\emph{\(caret)}") }
                .keyboardShortcut("i")
                .disabled(!editing)
        }

        CommandMenu("Build") {
            Button("Build Now") { model.build() }
                .keyboardShortcut("r")
                .disabled(!editing)
            Toggle("Build As I Type", isOn: Binding(get: { model.autoBuild }, set: { model.autoBuild = $0 }))
            Toggle("Autosave Every 10 Seconds", isOn: Binding(get: { model.autoSave }, set: { model.autoSave = $0 }))
            Divider()
            Toggle("Offline", isOn: Binding(get: { model.offline }, set: { _ in model.toggleOffline() }))
            Button("Download the LaTeX Essentials", action: model.setUp)
                .disabled(model.cache == .downloading)
        }

        CommandGroup(before: .toolbar) {
            Button("Command Palette…") { model.paletteOpen.toggle() }
                .keyboardShortcut("k")
            Divider()
            Button("Zoom In") { model.zoom(by: 1) }
                .keyboardShortcut("=")
                .disabled(!editing)
            Button("Zoom Out") { model.zoom(by: -1) }
                .keyboardShortcut("-")
                .disabled(!editing)
            Button("Fit to Width") { model.zoom = .fit }
                .keyboardShortcut("0")
                .disabled(!editing)
            Divider()
            Button(model.rightPane == .marks ? "Show Preview" : "Show Issues") {
                model.rightPane = model.rightPane == .marks ? .proof : .marks
            }
            .disabled(!editing || model.visible.isEmpty)
            Button(model.pressOpen ? "Hide Press Log" : "Show Press Log") { model.pressOpen.toggle() }
                .disabled(!editing)
            Button("Back to the Title Page") { model.screen = .welcome }
                .disabled(!editing)
            Divider()
        }
    }
}
