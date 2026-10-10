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
        EditorScreen()
            .frame(minWidth: 880, minHeight: 560)
            .scribeStyle()
            .sheet(isPresented: $session.paletteOpen) { PaletteView() }
            .sheet(isPresented: $session.exportOpen) {
                if let preview = session.preview {
                    ExportSheet(pdf: preview.data, documentSheet: sheetOf(session.source))
                }
            }
            .environment(session)
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
                // A document is open; the welcome window has done its job.
                dismissWindow(id: WelcomeView.windowID)
            }
    }
}
