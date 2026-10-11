import ScribeXCore
import SwiftUI

/// The menu bar. New, Open, Open Recent, Save, Save As, Revert, Rename and
/// Close come from the document system; ScribeX's own items come from
/// `Command.all`, the same list the palette searches.
public struct MenuBar: Commands {
    let engine: Engine
    @FocusedValue(\.session) private var session
    @FocusedValue(\.panels) private var panels
    @FocusedValue(\.zoom) private var zoom
    @FocusedValue(\.sheet) private var sheet
    @Environment(\.openWindow) private var openWindow

    public init(engine: Engine) {
        self.engine = engine
    }

    public var body: some Commands {
        let commands = Command.all(Command.Focus(session: session, panels: panels, zoom: zoom, sheet: sheet), engine: engine)

        // Show/Hide Sidebar (⌃⌘S) for the contents, as in any Mac app with a sidebar.
        SidebarCommands()
        CommandGroup(replacing: .appSettings) {}
        CommandGroup(replacing: .printItem) {}
        CommandGroup(after: .saveItem) {
            Divider()
            items(commands, in: .file)
        }
        CommandMenu("Format") { items(commands, in: .format) }
        CommandMenu("Build") {
            items(commands, in: .build)
            Divider()
            items(commands, in: .setup)
        }
        CommandGroup(before: .toolbar) {
            items(commands, in: .view)
            Divider()
        }
        CommandGroup(before: .windowList) {
            Button("Welcome to ScribeX") { openWindow(id: HomeView.windowID) }
                .keyboardShortcut("1", modifiers: [.command, .shift])
            Divider()
        }
    }

    private func items(_ commands: [Command], in menu: Command.Menu) -> some View {
        ForEach(commands.filter { $0.menu == menu && !$0.system }) { command in
            Group {
                if let isOn = command.isOn {
                    Toggle(command.title, isOn: Binding(get: { isOn }, set: { _ in command.run() }))
                } else {
                    Button(command.title, action: command.run)
                }
            }
            .keyboardShortcut(command.keys)
            .disabled(!command.isEnabled)
        }
    }
}
