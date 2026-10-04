import ScribeXUI
import SwiftUI

@main
struct ScribeXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The window is AppKit's (see AppDelegate); SwiftUI adds only the menus.
        Settings { EmptyView() }
            .commands { AppCommands(model: delegate.model) }
    }
}
