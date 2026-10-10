import ScribeXUI
import SwiftUI

@main
struct ScribeXApp: App {
    @State private var engine = Engine(worker: Engine.bundledWorker)

    init() {
        #if DEBUG
        DebugScript.runIfRequested()
        #endif
    }

    var body: some Scene {
        // Shown at launch instead of an untitled document, and from the Window menu.
        Window("Welcome to ScribeX", id: WelcomeView.windowID) {
            WelcomeView().environment(engine)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1280, height: 820)
        .defaultLaunchBehavior(.presented)
        // The Window menu lists it once, with a shortcut, from AppCommands.
        .commandsRemoved()

        DocumentGroup(newDocument: { TexDocument() }) { file in
            DocumentWindow(document: file.document, fileURL: file.fileURL, engine: engine)
                .environment(engine)
        }
        .defaultSize(width: 1280, height: 820)
        .defaultLaunchBehavior(.suppressed)
        .commands { AppCommands(engine: engine) }
    }
}
