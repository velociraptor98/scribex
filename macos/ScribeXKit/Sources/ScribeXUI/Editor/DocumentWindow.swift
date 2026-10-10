import ScribeXCore
import SwiftUI

/// The content of one document window. `DocumentGroup` makes one per open
/// document and supplies the title, proxy icon, edited dot and save prompts.
public struct DocumentWindow: View {
    @State private var session: Session
    private let fileURL: URL?
    @Environment(\.dismissWindow) private var dismissWindow

    public init(document: TexDocument, fileURL: URL?, engine: Engine) {
        let session = Session(document: document, engine: engine)
        session.fileURL = fileURL
        _session = State(initialValue: session)
        self.fileURL = fileURL
    }

    public var body: some View {
        @Bindable var session = session
        EditorScreen(model: session)
            .frame(minWidth: 880, minHeight: 560)
            .scribeStyle()
            .sheet(isPresented: $session.paletteOpen) { PaletteView(model: session) }
            .sheet(isPresented: $session.exportOpen) {
                if let preview = session.preview {
                    ExportSheet(model: session, pdf: preview.data, documentSheet: sheetOf(session.source))
                }
            }
            .environment(session.engine)
            .focusedSceneValue(\.session, session)
            .onChange(of: fileURL) { _, url in session.fileURL = url }
            .onChange(of: session.engine.cache) { _, cache in
                if cache == .ready { session.build() }
            }
            .onAppear {
                #if DEBUG
                Session.active = session
                #endif
                session.scheduleBuild()
            }
            .background(WindowProbe { window in
                // A document is open; the welcome window has done its job.
                // If it was full screen, this window takes its place there.
                let home = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(HomeView.windowID) == true }
                if home?.styleMask.contains(.fullScreen) == true, !window.styleMask.contains(.fullScreen) {
                    DispatchQueue.main.async { window.toggleFullScreen(nil) }
                }
                dismissWindow(id: HomeView.windowID)
            })
    }
}

/// Hands over the window the view lands in, for what SwiftUI can't do: enter full screen.
private struct WindowProbe: NSViewRepresentable {
    let found: (NSWindow) -> Void

    final class Probe: NSView {
        var found: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            if let window { found?(window); found = nil }
        }
    }

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.found = found
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) {}
}
