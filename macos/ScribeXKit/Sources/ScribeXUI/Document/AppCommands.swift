import ScribeXCore
import SwiftUI

/// The menu bar. New, Open, Open Recent, Save, Save As, Revert, Rename and
/// Close come from the document system; ScribeX's own items come from
/// `Command.all`, the same list the palette searches.
public struct AppCommands: Commands {
    let engine: Engine
    @FocusedValue(\.session) private var session
    @Environment(\.openWindow) private var openWindow

    public init(engine: Engine) {
        self.engine = engine
    }

    public var body: some Commands {
        let commands = Command.all(session: session, engine: engine)

        CommandGroup(replacing: .appSettings) {}
        CommandGroup(replacing: .printItem) {}
        CommandGroup(after: .saveItem) {
            Divider()
            items(commands, in: .file)
        }
        CommandMenu("Format") { items(commands, in: .format) }
        CommandMenu("Build") { items(commands, in: .build) }
        CommandGroup(before: .toolbar) {
            items(commands, in: .view)
            Divider()
        }
        CommandGroup(before: .windowList) {
            Button("Welcome to ScribeX") { openWindow(id: WelcomeView.windowID) }
                .keyboardShortcut("1", modifiers: [.command, .shift])
            Divider()
        }
    }

    private func items(_ commands: [Command], in menu: Command.Menu) -> some View {
        ForEach(commands.filter { $0.menu == menu }) { command in
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
