import ScribeXCore
import SwiftUI

/// The menu bar. New, Open, Open Recent, Save, Save As, Revert, Rename and
/// Close come from the document system; these are ScribeX's own.
public struct AppCommands: Commands {
    let engine: Engine
    @FocusedValue(\.session) private var session
    @Environment(\.openWindow) private var openWindow

    public init(engine: Engine) {
        self.engine = engine
    }

    public var body: some Commands {
        CommandGroup(replacing: .appSettings) {}
        CommandGroup(replacing: .printItem) {}

        CommandGroup(after: .saveItem) {
            Divider()
            Button("Export as PDF…") { session?.requestExport() }
                .keyboardShortcut("e")
                .disabled(session?.preview == nil)
        }

        CommandMenu("Format") {
            Group {
                Button("Bold") { session?.insert("\\textbf{\(caret)}") }
                    .keyboardShortcut("b")
                Button("Italic") { session?.insert("\\emph{\(caret)}") }
                    .keyboardShortcut("i")
            }
            .disabled(session == nil)
        }

        CommandMenu("Build") {
            Button("Build Now") { session?.build() }
                .keyboardShortcut("r")
                .disabled(session == nil)
            Toggle("Build As I Type", isOn: Binding(
                get: { session?.autoBuild ?? false },
                set: { session?.autoBuild = $0 }
            ))
            .disabled(session == nil)
            Divider()
            Toggle("Offline", isOn: Binding(get: { engine.offline }, set: { _ in engine.toggleOffline() }))
            Button("Download the LaTeX Essentials", action: engine.setUp)
                .disabled(engine.cache == .downloading)
        }

        CommandGroup(before: .toolbar) {
            Button("Command Palette…") { session?.paletteOpen.toggle() }
                .keyboardShortcut("k")
                .disabled(session == nil)
            Divider()
            Button("Zoom In") { session?.zoom(by: 1) }
                .keyboardShortcut("=")
                .disabled(session == nil)
            Button("Zoom Out") { session?.zoom(by: -1) }
                .keyboardShortcut("-")
                .disabled(session == nil)
            Button("Fit to Width") { session?.zoom = .fit }
                .keyboardShortcut("0")
                .disabled(session == nil)
            Divider()
            Button(session?.rightPane == .marks ? "Show Preview" : "Show Issues") {
                guard let session else { return }
                session.rightPane = session.rightPane == .marks ? .proof : .marks
            }
            .disabled(session?.visible.isEmpty ?? true)
            Button(session?.pressOpen == true ? "Hide Press Log" : "Show Press Log") { session?.pressOpen.toggle() }
                .disabled(session == nil)
            Divider()
        }

        CommandGroup(before: .windowList) {
            Button("Welcome to ScribeX") { openWindow(id: WelcomeView.windowID) }
                .keyboardShortcut("1", modifiers: [.command, .shift])
            Divider()
        }
    }
}
