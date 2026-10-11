import ScribeXCore
import SwiftUI

/// Which parts of the window are showing. The source always is.
struct Panels: Equatable {
    var contents = true
    var preview = true
    var issues = false
}

/// The sheets a document window can show, one at a time.
enum DocumentSheet: Identifiable {
    case palette, export
    var id: Self { self }
}

/// One document window: contents · source · preview side by side, with the
/// issues accordion beneath the preview. `DocumentGroup` makes one per open
/// document and supplies the title, proxy icon, edited dot and save prompts.
///
/// Contents and preview can be closed, the issues folded, and the split resizes them. The
/// window's own state (panels, zoom, the open sheet) lives here, the nearest
/// view its parts share, and reaches the menu bar through focus.
public struct DocumentView: View {
    @State private var session: Session
    private let fileURL: URL?
    @State private var panels = Panels()
    @State private var zoom = Zoom()
    @State private var sheet: DocumentSheet?
    @Environment(\.dismissWindow) private var dismissWindow

    public init(document: TexDocument, fileURL: URL?, engine: Engine) {
        let session = Session(document: document, engine: engine)
        session.fileURL = fileURL
        _session = State(initialValue: session)
        self.fileURL = fileURL
    }

    public var body: some View {
        VStack(spacing: 0) {
            Setup(compact: true)
            HSplitView {
                if panels.contents {
                    Contents(model: session).frame(minWidth: 150, idealWidth: 190, maxWidth: 300)
                }
                Editor(model: session).frame(minWidth: 300)
                    // A lighter edge beside the split's own dark line.
                    .overlay(alignment: .trailing) { Rectangle().fill(.separator).frame(width: 1) }
                if panels.preview {
                    Renderer(model: session, zoom: $zoom) { sheet = .export }
                        .overlay(alignment: .bottom) {
                            // Capped only when open: a max frame takes the whole height
                            // it allows, which would lift the folded header off the foot.
                            Issues(model: session, isExpanded: $panels.issues)
                                .frame(maxHeight: panels.issues ? 320 : nil)
                        }
                        .frame(minWidth: 320, idealWidth: 560)
                } else if panels.issues {
                    Issues(model: session, isExpanded: $panels.issues).frame(minWidth: 320, idealWidth: 560)
                }
            }
        }
        // Typing resumes where it left off once a sheet closes.
        .sheet(item: $sheet, onDismiss: session.editor.focus) { which in
            switch which {
            case .palette:
                Palette(commands: Command.all(focus, engine: session.engine),
                        hasSelection: !session.editor.selectedText.isEmpty, insert: session.insert)
            case .export:
                if let preview = session.preview {
                    ExportSheet(model: session, pdf: preview.data, documentSheet: sheetOf(session.source))
                }
            }
        }
        .focusedSceneValue(\.panels, $panels)
        .focusedSceneValue(\.zoom, $zoom)
        .focusedSceneValue(\.sheet, $sheet)
        #if DEBUG
        .onAppear { DebugScript.focus = focus }
        #endif
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Contents", systemImage: "sidebar.left") { panels.contents.toggle() }
                    .help(panels.contents ? "Hide the contents (⌃⌘S)" : "Show the contents (⌃⌘S)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if let last = session.fetched.last {
                    ProgressView().controlSize(.small)
                    Text("Downloading \(last)").font(Fonts.text(11.5)).foregroundStyle(.secondary)
                }
            }
            // Status rather than an action, so no glass capsule behind it.
            .sharedBackgroundVisibility(.hidden)
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Issues", systemImage: "rectangle.bottomthird.inset.filled") { panels.issues.toggle() }
                    .badge(session.visible.count)
                    .help(panels.issues ? "Hide the issues (⇧⌘M)" : "Show the issues (⇧⌘M)")
                Button("Preview", systemImage: "sidebar.right") { panels.preview.toggle() }
                    .help(panels.preview ? "Hide the preview (⌥⌘P)" : "Show the preview (⌥⌘P)")
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .scribeStyle()
        .environment(session.engine)
        .focusedSceneValue(\.session, session)
        .onChange(of: fileURL) { _, url in session.fileURL = url }
        .onChange(of: session.engine.cache) { _, cache in
            if cache == .ready { session.build() }
        }
        .onAppear { session.scheduleBuild() }
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

    /// The palette's commands act on this window's state directly.
    private var focus: Command.Focus {
        Command.Focus(session: session, panels: $panels, zoom: $zoom, sheet: $sheet)
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

#Preview {
    DocumentView(document: TexDocument(), fileURL: nil, engine: .preview)
        .frame(width: 1280, height: 820)
}
