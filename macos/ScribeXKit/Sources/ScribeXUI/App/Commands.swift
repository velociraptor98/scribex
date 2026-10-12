import AppKit
import ScribeXCore
import SwiftUI

/// Something ScribeX can do, defined once for the menu bar and the ⌘K palette.
struct Command: Identifiable {
    /// Its group: where it sits in the menu bar, and the heading it comes
    /// under in the palette, in this order.
    enum Menu: CaseIterable {
        case file, format, build, view
        /// One-off downloads, at the foot of the Build menu and the palette.
        case setup

        var title: String {
            switch self {
            case .file: "File"
            case .format: "Format"
            case .build: "Build"
            case .view: "View"
            case .setup: "Setup"
            }
        }
    }

    let id: String
    let title: String
    var keys: KeyboardShortcut?
    /// Extra words the palette matches on, beyond the title.
    var words: [String] = []
    /// Its group: the menu it sits in, and its heading in the palette.
    var menu: Menu = .file
    /// macOS already puts it in the menu bar (Save, Show Sidebar…); ScribeX
    /// only offers it in the palette.
    var system = false
    var inPalette = true
    /// Set for an on/off setting, shown with a checkmark in the menu.
    var isOn: Bool?
    var isEnabled = true
    let run: () -> Void

    /// What the commands act on in the front document window: its session, and
    /// the state its views keep, reached through bindings.
    struct Focus {
        var session: Session?
        var panels: Binding<Panels>?
        var zoom: Binding<Zoom>?
        var sheet: Binding<DocumentSheet?>?
    }

    /// Everything, for the front document window if there is one.
    static func all(_ focus: Focus, engine: Engine) -> [Command] {
        let session = focus.session
        let open = session != nil
        let previewShown = focus.zoom != nil && focus.panels?.wrappedValue.preview == true
        let send = { (action: Selector) in { NSApp.sendAction(action, to: nil, from: nil); return } }
        return [
            // File: macOS's own menu items, offered in the palette too.
            Command(id: "new", title: "New Document", keys: KeyboardShortcut("n"), words: ["blank", "start"], system: true,
                    isEnabled: !engine.locked) { NSDocumentController.shared.newDocument(nil) },
            Command(id: "open", title: "Open…", keys: KeyboardShortcut("o"), words: ["file", "document"], system: true,
                    isEnabled: !engine.locked) { NSDocumentController.shared.openDocument(nil) },
            Command(id: "save", title: "Save", keys: KeyboardShortcut("s"), words: ["write", "disk"], system: true,
                    isEnabled: open, run: send(#selector(NSDocument.save(_:)))),
            Command(id: "saveas", title: "Save As…", keys: KeyboardShortcut("s", modifiers: [.command, .shift]),
                    words: ["copy", "rename"], system: true, isEnabled: open, run: send(#selector(NSDocument.saveAs(_:)))),
            Command(id: "export", title: "Export as PDF…", keys: KeyboardShortcut("e"), words: ["pdf", "print"],
                    menu: .file, isEnabled: session?.typesetting.preview != nil) { focus.sheet?.wrappedValue = .export },

            // Format. The palette has richer snippets for these.
            Command(id: "bold", title: "Bold", keys: KeyboardShortcut("b"), menu: .format, inPalette: false,
                    isEnabled: open) { session?.insert("\\textbf{\(caret)}") },
            Command(id: "italic", title: "Italic", keys: KeyboardShortcut("i"), menu: .format, inPalette: false,
                    isEnabled: open) { session?.insert("\\emph{\(caret)}") },

            // Build.
            Command(id: "build", title: "Build Now", keys: KeyboardShortcut("r"), words: ["compile", "typeset", "rebuild"],
                    menu: .build, isEnabled: open && session?.typesetting.busy == false) { session?.typesetting.build() },
            Command(id: "live", title: "Build As I Type", words: ["live", "auto", "rebuild"], menu: .build,
                    isOn: session?.typesetting.autoBuild ?? false, isEnabled: open) { session?.typesetting.autoBuild.toggle() },
            Command(id: "prime", title: "Download the LaTeX Essentials", words: ["cache", "offline", "network", "download", "packages", "fonts", "setup"],
                    menu: .setup, isEnabled: engine.cache != .downloading) { engine.setUp() },

            // View.
            Command(id: "palette", title: "Command Palette…", keys: KeyboardShortcut("k"), menu: .view, inPalette: false,
                    isEnabled: open) { focus.sheet?.wrappedValue = .palette },
            Command(id: "zoomin", title: "Zoom In", keys: KeyboardShortcut("="), words: ["enlarge", "bigger", "preview"],
                    menu: .view, isEnabled: previewShown) { focus.zoom?.wrappedValue.step(1) },
            Command(id: "zoomout", title: "Zoom Out", keys: KeyboardShortcut("-"), words: ["reduce", "smaller", "preview"],
                    menu: .view, isEnabled: previewShown) { focus.zoom?.wrappedValue.step(-1) },
            Command(id: "zoomfit", title: "Fit to Width", keys: KeyboardShortcut("0"), words: ["zoom", "fit", "reset", "preview"],
                    menu: .view, isEnabled: previewShown) { focus.zoom?.wrappedValue.fit = true },
            Command(id: "contents", title: focus.panels?.wrappedValue.contents == false ? "Show Contents" : "Hide Contents",
                    keys: KeyboardShortcut("s", modifiers: [.control, .command]), words: ["outline", "sections", "sidebar"],
                    menu: .view, system: true, isEnabled: open) { focus.panels?.wrappedValue.contents.toggle() },
            Command(id: "preview", title: focus.panels?.wrappedValue.preview == false ? "Show Preview" : "Hide Preview",
                    keys: KeyboardShortcut("p", modifiers: [.option, .command]), words: ["pdf", "pages", "renderer"],
                    menu: .view, isEnabled: open) { focus.panels?.wrappedValue.preview.toggle() },
            Command(id: "issues", title: focus.panels?.wrappedValue.issues == true ? "Hide Issues" : "Show Issues",
                    keys: KeyboardShortcut("m", modifiers: [.shift, .command]), words: ["errors", "warnings", "problems"],
                    menu: .view, isEnabled: open) { focus.panels?.wrappedValue.issues.toggle() },
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

extension FocusedValues {
    /// The front document window's session and view state, for the menu bar.
    @Entry public var session: Session?
    @Entry var panels: Binding<Panels>?
    @Entry var zoom: Binding<Zoom>?
    @Entry var sheet: Binding<DocumentSheet?>?
}
