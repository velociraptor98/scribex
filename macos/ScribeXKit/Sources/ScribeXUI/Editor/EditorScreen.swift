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

/// Contents · source · preview side by side, with the issues panel beneath
/// the preview. Every part but the source can be closed; the splits resize
/// them. The window's own state lives here, the nearest view that all its
/// users share, and reaches the menu bar through focus.
struct EditorScreen: View {
    let model: Session
    @State private var panels = Panels()
    @State private var zoom = Zoom()
    @State private var sheet: DocumentSheet?

    var body: some View {
        VStack(spacing: 0) {
            SetupView(compact: true)
            banners
            HSplitView {
                if panels.contents {
                    Contents(model: model, isOpen: $panels.contents).frame(minWidth: 150, idealWidth: 190, maxWidth: 300)
                }
                Editor(model: model).frame(minWidth: 300)
                if panels.preview || panels.issues {
                    VSplitView {
                        if panels.preview {
                            Renderer(model: model, zoom: $zoom) { sheet = .export }.frame(minHeight: 240)
                        }
                        if panels.issues {
                            Issues(model: model, isOpen: $panels.issues).frame(minHeight: 100, idealHeight: 220)
                        }
                    }
                    .frame(minWidth: 320, idealWidth: 560)
                }
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .palette:
                PaletteView(model: model, commands: Command.all(focus, engine: model.engine))
            case .export:
                if let preview = model.preview {
                    ExportSheet(model: model, pdf: preview.data, documentSheet: sheetOf(model.source))
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
                if let last = model.fetched.last {
                    ProgressView().controlSize(.small)
                    Text("Downloading \(last)").font(Fonts.text(11.5)).foregroundStyle(.secondary)
                }
                // A button, not a toggle: a toolbar toggle that is on draws as a
                // white disc, and offline is the normal state.
                Button(action: model.toggleOffline) {
                    Label(model.offline ? "Offline" : "Network", systemImage: model.offline ? "wifi.slash" : "wifi")
                        .labelStyle(.titleAndIcon)
                }
                .help(model.offline ? "The engine refuses all network access" : "The engine may fetch missing resources")
            }
            // Status rather than an action, so no glass capsule behind it.
            .sharedBackgroundVisibility(.hidden)
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Issues", systemImage: "rectangle.bottomthird.inset.filled") { panels.issues.toggle() }
                    .badge(model.visible.count)
                    .help(panels.issues ? "Hide the issues (⇧⌘M)" : "Show the issues (⇧⌘M)")
                Button("Preview", systemImage: "sidebar.right") { panels.preview.toggle() }
                    .help(panels.preview ? "Hide the preview (⌥⌘P)" : "Show the preview (⌥⌘P)")
            }
        }
    }

    /// The palette's commands act on this window's state directly.
    private var focus: Command.Focus {
        Command.Focus(session: model, panels: $panels, zoom: $zoom, sheet: $sheet)
    }

    @ViewBuilder private var banners: some View {
        if let missing = model.missing, model.engine.cache == .ready {
            Banner {
                Text("\(Text(missing).monospaced().foregroundStyle(.gilt)) is not in the offline cache.")
                Button("Fetch it") { model.build(allowNetwork: true) }.buttonStyle(.borderedProminent)
                Button("Download the essentials", action: model.setUp)
                Text("both need the network, once").italic().foregroundStyle(.secondary)
            }
            .disabled(model.busy)
        }
        if let absent = model.absent {
            Banner {
                Text("\(Text(absent).monospaced().foregroundStyle(.gilt)) was not found. It is not part of the TeX distribution — put it in the same folder as \(model.name).")
                if model.fileURL != nil { Button("Show the folder", action: model.revealFolder) }
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

#Preview {
    let session = Session.preview()
    EditorScreen(model: session)
        .environment(session.engine)
        .scribeStyle()
        .frame(width: 1280, height: 820)
}
