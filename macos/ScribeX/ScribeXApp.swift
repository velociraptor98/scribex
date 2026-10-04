import ScribeXUI
import SwiftUI

@main
struct ScribeXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The window is AppKit's, so closing it can wait on unsaved work (see
        // AppShell.swift in ScribeXUI). SwiftUI contributes the menu bar.
        Settings { EmptyView() }
            .commands { AppCommands(model: delegate.model) }
    }
}
