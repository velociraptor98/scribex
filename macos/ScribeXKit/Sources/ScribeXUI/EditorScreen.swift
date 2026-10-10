import ScribeXCore
import SwiftUI

/// Contents · source · preview, with the press log along the foot.
struct EditorScreen: View {
    let model: Session

    var body: some View {
        VStack(spacing: 0) {
            SetupView(compact: true)
            banners
            HSplitView {
                ContentsPane(model: model).frame(minWidth: 150, idealWidth: 190, maxWidth: 300)
                SourceEditor(model: model).frame(minWidth: 300)
                PreviewPane(model: model).frame(minWidth: 320, idealWidth: 560)
            }
            PressLogView(model: model)
        }
        .toolbar {
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
        }
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

private struct ContentsPane: View {
    let model: Session

    var body: some View {
        let sections = model.sections
        // Indent relative to the shallowest heading present, so an article whose
        // top level is \section is not pushed in by levels it never uses.
        let base = sections.map(\.level).min() ?? 0
        let tally = model.tally

        VStack(alignment: .leading, spacing: 0) {
            Text("Contents").smallCaps().padding(16)
            List(sections.indices, id: \.self) { i in
                let entry = sections[i]
                Button { model.editor.goto(entry.line) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(entry.number).foregroundStyle(.tertiary).monospacedDigit()
                        Text(entry.title.isEmpty ? "Untitled" : entry.title).italic(entry.title.isEmpty)
                    }
                    .padding(.leading, CGFloat(entry.level - base) * 12)
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Line \(entry.line)")
            }
            .scrollContentBackground(.hidden)
            .overlay { if sections.isEmpty { Text("No sections yet").italic().foregroundStyle(.secondary) } }
            Text("\(plural(tally.sections, "section")) · \(plural(tally.equations, "equation"))\n\(plural(tally.citations, "citation"))")
                .font(Fonts.text(11.5)).foregroundStyle(.secondary).padding(16)
        }
    }

    private func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
}

private struct PreviewPane: View {
    let model: Session
    /// Reported by the PDF view as it scrolls; nothing else needs them.
    @State private var pages = 0
    @State private var page = 1

    var body: some View {
        @Bindable var model = model
        let issues = model.visible.count

        VStack(spacing: 0) {
            HStack {
                Picker("Show", selection: $model.rightPane) {
                    Text("Preview").tag(Session.RightPane.proof)
                    Text(issues > 0 ? "Issues · \(issues)" : "Issues").tag(Session.RightPane.marks)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button("Export PDF…", action: model.requestExport)
                    .disabled(model.preview == nil || model.busy)
            }
            .padding(12)

            Group {
                if model.rightPane == .proof {
                    PreviewView(preview: model.preview, zoom: model.zoom,
                                onScale: { model.scale = $0 }, onPages: { pages = $0 }, onPage: { page = $0 })
                        .overlay { if model.preview == nil { Text("Nothing built yet").italic().foregroundStyle(.secondary) } }
                } else {
                    MarksView(model: model)
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                Text(pages > 0 ? "Page \(min(page, pages)) of \(pages)" : "No preview yet")
                Spacer()
                if model.rightPane == .proof { zoomControls }
                Spacer()
                Text(model.status).lineLimit(1).opacity(model.busy ? 0.6 : 1)
            }
            .font(Fonts.text(11.5))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .controlSize(.small)
            .padding(12)
        }
        .background(.sunken)
    }

    private var zoomControls: some View {
        HStack(spacing: 6) {
            ControlGroup {
                Button("Zoom Out", systemImage: "minus") { model.zoom(by: -1) }.disabled(model.scale <= Session.minZoom)
                Button("Zoom In", systemImage: "plus") { model.zoom(by: 1) }.disabled(model.scale >= Session.maxZoom)
            }
            .fixedSize()
            Button("\(Int((model.scale * 100).rounded()))%") { model.zoom = .scale(1) }
                .buttonStyle(.borderless)
                .help("Actual size")
            Toggle("Fit", isOn: Binding(get: { model.zoom == .fit }, set: { model.zoom = $0 ? .fit : .scale(model.scale) }))
                .toggleStyle(.button)
                .help("Fit to width (⌘0)")
        }
    }
}

#Preview {
    let session = Session.preview()
    EditorScreen(model: session)
        .environment(session.engine)
        .scribeStyle()
        .frame(width: 1280, height: 820)
}
