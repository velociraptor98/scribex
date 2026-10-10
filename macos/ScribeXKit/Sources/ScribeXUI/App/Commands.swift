import AppKit
import ScribeXCore
import SwiftUI

/// Something ScribeX can do, defined once for the menu bar and the ⌘K palette.
struct Command: Identifiable {
    enum Menu { case file, format, build, view }

    let id: String
    let title: String
    var keys: KeyboardShortcut?
    /// Extra words the palette matches on, beyond the title.
    var words: [String] = []
    /// Where it sits in the menu bar; nil for what macOS already provides there.
    var menu: Menu?
    var inPalette = true
    /// Set for an on/off setting, shown with a checkmark in the menu.
    var isOn: Bool?
    var isEnabled = true
    let run: () -> Void

    /// Everything, for the front document (`session`) if there is one.
    static func all(session: Session?, engine: Engine) -> [Command] {
        let open = session != nil
        let send = { (action: Selector) in { NSApp.sendAction(action, to: nil, from: nil); return } }
        return [
            // File: macOS's own menu items, offered in the palette too.
            Command(id: "new", title: "New Document", keys: KeyboardShortcut("n"), words: ["blank", "start"],
                    isEnabled: !engine.locked) { NSDocumentController.shared.newDocument(nil) },
            Command(id: "open", title: "Open…", keys: KeyboardShortcut("o"), words: ["file", "document"],
                    isEnabled: !engine.locked) { NSDocumentController.shared.openDocument(nil) },
            Command(id: "save", title: "Save", keys: KeyboardShortcut("s"), words: ["write", "disk"],
                    isEnabled: open, run: send(#selector(NSDocument.save(_:)))),
            Command(id: "saveas", title: "Save As…", keys: KeyboardShortcut("s", modifiers: [.command, .shift]),
                    words: ["copy", "rename"], isEnabled: open, run: send(#selector(NSDocument.saveAs(_:)))),
            Command(id: "export", title: "Export as PDF…", keys: KeyboardShortcut("e"), words: ["pdf", "print"],
                    menu: .file, isEnabled: session?.preview != nil) { session?.requestExport() },

            // Format. The palette has richer snippets for these.
            Command(id: "bold", title: "Bold", keys: KeyboardShortcut("b"), menu: .format, inPalette: false,
                    isEnabled: open) { session?.insert("\\textbf{\(caret)}") },
            Command(id: "italic", title: "Italic", keys: KeyboardShortcut("i"), menu: .format, inPalette: false,
                    isEnabled: open) { session?.insert("\\emph{\(caret)}") },

            // Build.
            Command(id: "build", title: "Build Now", keys: KeyboardShortcut("r"), words: ["compile", "typeset", "rebuild"],
                    menu: .build, isEnabled: open && session?.busy == false) { session?.build() },
            Command(id: "live", title: "Build As I Type", words: ["live", "auto", "rebuild"], menu: .build,
                    isOn: session?.autoBuild ?? false, isEnabled: open) { session?.autoBuild.toggle() },
            Command(id: "offline", title: "Offline", words: ["network", "online", "cache", "download"], menu: .build,
                    isOn: engine.offline) { engine.toggleOffline() },
            Command(id: "prime", title: "Download the LaTeX Essentials", words: ["cache", "offline", "packages", "fonts", "setup"],
                    menu: .build, isEnabled: engine.cache != .downloading) { engine.setUp() },

            // View.
            Command(id: "palette", title: "Command Palette…", keys: KeyboardShortcut("k"), menu: .view, inPalette: false,
                    isEnabled: open) { session?.paletteOpen.toggle() },
            Command(id: "zoomin", title: "Zoom In", keys: KeyboardShortcut("="), words: ["enlarge", "bigger", "preview"],
                    menu: .view, isEnabled: open) { session?.zoom(by: 1) },
            Command(id: "zoomout", title: "Zoom Out", keys: KeyboardShortcut("-"), words: ["reduce", "smaller", "preview"],
                    menu: .view, isEnabled: open) { session?.zoom(by: -1) },
            Command(id: "zoomfit", title: "Fit to Width", keys: KeyboardShortcut("0"), words: ["zoom", "fit", "reset", "preview"],
                    menu: .view, isEnabled: open) { session?.zoom = .fit },
            Command(id: "issues", title: session?.rightPane == .marks ? "Show Preview" : "Show Issues",
                    words: ["errors", "warnings", "problems"], menu: .view,
                    isEnabled: !(session?.visible.isEmpty ?? true)) {
                guard let session else { return }
                session.rightPane = session.rightPane == .marks ? .proof : .marks
            },
            Command(id: "presslog", title: session?.pressOpen == true ? "Hide Press Log" : "Show Press Log",
                    words: ["log", "tex", "passes"], menu: .view, isEnabled: open) { session?.pressOpen.toggle() },
        ]
    }

    /// The title as the palette lists it: a setting that is on is ticked, as
    /// in the menu.
    var label: String { isOn == true ? "\(title) ✓" : title }

    /// How the palette shows the shortcut, e.g. "⇧⌘S".
    var hint: String? {
        keys.map { keys in
            let m = keys.modifiers
            return (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "")
                + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "")
                + String(keys.key.character).uppercased()
        }
    }
}
