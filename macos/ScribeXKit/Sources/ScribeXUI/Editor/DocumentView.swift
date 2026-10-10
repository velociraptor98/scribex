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
            SetupView(compact: true)
            banners
            HSplitView {
                if panels.contents {
                    Contents(model: session).frame(minWidth: 150, idealWidth: 190, maxWidth: 300)
                }
                Editor(model: session).frame(minWidth: 300)
                    .background(ThickDividers())
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
        .sheet(item: $sheet) { which in
            switch which {
            case .palette:
                PaletteView(model: session, commands: Command.all(focus, engine: session.engine))
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

    @ViewBuilder private var banners: some View {
        if let missing = session.missing, session.engine.cache == .ready {
            Banner {
                Text("\(Text(missing).monospaced().foregroundStyle(.gilt)) is not in the offline cache.")
                Button("Fetch it") { session.build(allowNetwork: true) }.buttonStyle(.borderedProminent)
                Button("Download the essentials", action: session.setUp)
                Text("both need the network, once").italic().foregroundStyle(.secondary)
            }
            .disabled(session.busy)
        }
        if let absent = session.absent {
            Banner {
                Text("\(Text(absent).monospaced().foregroundStyle(.gilt)) was not found. It is not part of the TeX distribution — put it in the same folder as \(session.name).")
                if session.fileURL != nil { Button("Show the folder", action: session.revealFolder) }
            }
        }
    }
}

/// A strip under the toolbar for something that needs a decision.
private struct Banner<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) { content; Spacer(minLength: 0) }
            .font(Fonts.text(12.5))
            .lineLimit(2)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.gilt.opacity(0.12))
    }
}

/// HSplitView has no say over its dividers, so this reaches the NSSplitView
/// behind it: a thick divider is an easier target to grab than the hairline.
private struct ThickDividers: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            // The split view adopts its panes after they move into the window.
            DispatchQueue.main.async { [weak self] in
                var view = self?.superview
                while let next = view, !(next is NSSplitView) { view = next.superview }
                (view as? NSSplitView)?.dividerStyle = .thick
            }
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ probe: Probe, context: Context) {}
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
