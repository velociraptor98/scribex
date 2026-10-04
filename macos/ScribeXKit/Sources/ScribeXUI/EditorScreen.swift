import ScribeXCore
import SwiftUI

struct EditorScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(title: model.name + (model.dirty ? " ·" : "")) {
                indicators
            }

            SetupView(compact: true)

            if let missing = model.missing, model.cache == .ready {
                Banner {
                    Text("\(Text(missing).font(Fonts.mono(12.5)).foregroundStyle(Tone.accent300)) is not in the offline cache.")
                        .lineLimit(1)
                    Button("Fetch it") { model.build(allowNetwork: true) }
                        .buttonStyle(InkButtonStyle(primary: true, size: .small))
                    Button("Download the essentials", action: model.setUp)
                        .buttonStyle(InkButtonStyle(size: .small))
                    Text("both need the network, once").bannerNote()
                }
                .disabled(model.busy)
            }

            if let absent = model.absent {
                Banner {
                    Text("\(Text(absent).font(Fonts.mono(12.5)).foregroundStyle(Tone.accent300)) was not found. It is not part of the TeX distribution, so it cannot be downloaded — put it in the same folder as \(model.name).")
                        .lineLimit(2)
                    if model.path != nil {
                        Button("Show the folder", action: model.revealFolder)
                            .buttonStyle(InkButtonStyle(size: .small))
                    }
                }
            }

            GeometryReader { geo in
                let narrow = geo.size.width < 1040
                HStack(spacing: 0) {
                    ContentsMargin(narrow: narrow)
                    SourceEditor(model: model)
                        .frame(minWidth: 0, maxWidth: .infinity)
                    Fold()
                    Recto(narrow: narrow)
                        .frame(width: rectoWidth(geo.size.width, narrow: narrow))
                }
            }

            PressLogView()
        }
    }

    private func rectoWidth(_ width: CGFloat, narrow: Bool) -> CGFloat {
        min(640, max(narrow ? 300 : 360, width * 0.46))
    }

    @ViewBuilder private var indicators: some View {
        if model.autosaving != .idle {
            let saving = model.autosaving == .saving
            HStack(spacing: 7) {
                Dot(color: saving ? Tone.accent : Tone.text42, pulsing: saving, period: 0.7)
                Text(saving ? "Autosaving…" : "Autosaved")
            }
            .font(Fonts.body(11))
            .foregroundStyle(saving ? Tone.accent300 : Tone.text42)
            .transition(.opacity)
        }
        if let last = model.fetched.last {
            HStack(spacing: 7) {
                Dot(color: Tone.accent, pulsing: true)
                Text("Downloading \(last)" + (model.fetched.count > 1 ? " · \(model.fetched.count)" : ""))
                    .monospacedDigit()
            }
            .font(Fonts.body(11))
            .foregroundStyle(Tone.accent300)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 280, alignment: .trailing)
            .help(model.fetched.joined(separator: "\n"))
        }
        Button(action: model.toggleOffline) {
            HStack(spacing: 7) {
                // Network allowed is the exceptional state, so it is the one that is hollow.
                Dot(color: Tone.accent, hollow: !model.offline)
                Text(model.offline ? "Offline" : "Network")
            }
            .font(Fonts.body(11))
        }
        .buttonStyle(HoverButtonStyle(color: Tone.text42, hover: Tone.text70))
        .help(model.offline ? "The engine refuses all network access" : "The engine may fetch missing resources")
    }
}

private struct Fold: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: Tone.accent.opacity(0.5), location: 0.12),
                .init(color: Tone.accent.opacity(0.5), location: 0.88),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(width: 1)
    }
}

private struct ContentsMargin: View {
    @Environment(AppModel.self) private var model
    var narrow: Bool

    var body: some View {
        let sections = model.sections
        // Indent relative to the shallowest heading present, so an article whose
        // top level is \section is not pushed in by the two levels (part,
        // chapter) it never uses — the margin is only 186px wide.
        let base = sections.map(\.level).min() ?? 0
        let tally = model.tally

        VStack(alignment: .leading, spacing: 0) {
            Text("Contents").rubric().padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, entry in
                        ContentsRow(entry: entry, indent: CGFloat(entry.level - base) * 11) {
                            model.editor.goto(entry.line)
                        }
                    }
                    if sections.isEmpty {
                        Text("No sections yet")
                            .font(Fonts.body(12, italic: true))
                            .foregroundStyle(Tone.text38)
                    }
                }
                .padding(.horizontal, narrow ? 14 : 20)
            }
            .padding(.horizontal, narrow ? -14 : -20)
            .scrollIndicators(.never)

            Hairline().padding(.vertical, 22)

            Text("\(count(tally.sections, "section")) · \(count(tally.equations, "equation"))\n\(count(tally.citations, "citation"))")
                .font(Fonts.body(11.5))
                .lineSpacing(11.5 * 0.7)
                .foregroundStyle(Tone.text42)

            Spacer(minLength: 16)

            HStack(spacing: 9) {
                let saving = model.autosaving == .saving
                Dot(color: model.dirty || saving ? Tone.accent : Tone.text.opacity(0.28), pulsing: saving, period: 0.7)
                Text(state)
                    .lineLimit(2)
            }
            .font(Fonts.body(11.5))
            .foregroundStyle(Tone.text42)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Hairline(color: Tone.rule10) }
        }
        .padding(.vertical, narrow ? 22 : 26)
        .padding(.horizontal, narrow ? 14 : 20)
        .frame(width: narrow ? 150 : 186)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .trailing) { Hairline(color: Tone.rule10, vertical: true) }
    }

    private var state: String {
        if model.autosaving == .saving { return "Autosaving…" }
        if !model.dirty { return "Saved" }
        return model.autoSave && model.path != nil ? "Unsaved · autosaves every 10 s" : "Unsaved changes"
    }

    private func count(_ n: Int, _ word: String) -> String {
        "\(n) \(word)\(n == 1 ? "" : "s")"
    }
}

private struct ContentsRow: View {
    var entry: OutlineEntry
    var indent: CGFloat
    var go: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: go) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if !entry.number.isEmpty {
                    Text(entry.number)
                        .monospacedDigit()
                        .foregroundStyle(hovering ? Tone.accent : Tone.text38)
                }
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .italic(entry.title.isEmpty)
                    .foregroundStyle(entry.title.isEmpty ? Tone.text38 : hovering ? Tone.text : Tone.text70)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .font(Fonts.body(13.5))
            .padding(.vertical, 7)
            .padding(.leading, 9 + indent)
            .padding(.trailing, 9)
            .background(hovering ? Tone.text.opacity(0.04) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -9)
        .onHover { hovering = $0 }
        .help("line \(entry.line)")
    }
}

private struct Recto: View {
    @Environment(AppModel.self) private var model
    var narrow: Bool

    var body: some View {
        @Bindable var model = model
        let visible = model.visible

        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Tab(label: "Preview", on: model.rightPane == .proof) { model.rightPane = .proof }
                Tab(
                    label: "Issues" + (visible.isEmpty ? "" : " · \(visible.count)"),
                    on: model.rightPane == .marks,
                    alert: visible.contains { $0.severity == .error }
                ) { model.rightPane = .marks }
                    .disabled(visible.isEmpty)
                Spacer()
                Button("Export PDF", action: model.requestExport)
                    .buttonStyle(InkButtonStyle(size: .small))
                    .disabled(model.preview == nil || model.busy)
                    .help("Export as PDF (⌘E)")
            }
            .padding(.top, 22)
            .padding(.bottom, 14)

            Group {
                if model.rightPane == .proof {
                    PreviewView(
                        preview: model.preview,
                        zoom: model.zoom,
                        onScale: { model.scale = $0 },
                        onPages: { model.pages = $0 },
                        onPage: { model.page = $0 }
                    )
                    .overlay {
                        if model.preview == nil {
                            Text("Nothing built yet")
                                .font(Fonts.body(12.5, italic: true))
                                .foregroundStyle(Tone.text38)
                        }
                    }
                } else {
                    MarksView()
                }
            }
            .frame(maxHeight: .infinity)

            footer
        }
        .padding(.horizontal, narrow ? 20 : 34)
        .padding(.bottom, narrow ? 22 : 30)
        .background(Tone.inkDeep)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(model.pages > 0 ? "Page \(min(model.page, model.pages)) of \(model.pages)" : "No preview yet")
                .fixedSize()
            Spacer(minLength: 0)
            if model.rightPane == .proof {
                ZoomControls()
            }
            Spacer(minLength: 0)
            Text(model.status)
                .lineLimit(1)
                .truncationMode(.tail)
                .pulsing(model.busy)
        }
        .font(Fonts.body(11))
        .monospacedDigit()
        .foregroundStyle(Tone.text42)
        .padding(.top, 16)
    }
}

private struct Tab: View {
    var label: String
    var on: Bool
    var alert = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .padding(.bottom, 5)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(on ? Tone.accent : .clear).frame(height: 1)
                }
        }
        .buttonStyle(HoverButtonStyle(
            // A failed build flags the Issues tab rather than switching to it.
            color: on ? Tone.accent : alert ? Tone.accent300 : Tone.text38,
            hover: on ? Tone.accent : Tone.text70
        ))
        .font(Fonts.body(10.5))
        .textCase(.uppercase)
        .tracking(10.5 * 0.18)
    }
}

private struct ZoomControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 2) {
            ZoomButton(label: "−", size: 14) { model.zoom(by: -1) }
                .disabled(model.scale <= AppModel.minZoom)
                .help("Zoom out (⌘−)")
            ZoomButton(label: "\(Int((model.scale * 100).rounded()))%") { model.zoom = .scale(1) }
                .frame(minWidth: 46)
                .help("Actual size")
            ZoomButton(label: "+", size: 14) { model.zoom(by: 1) }
                .disabled(model.scale >= AppModel.maxZoom)
                .help("Zoom in (⌘+)")
            ZoomButton(label: "FIT", size: 10, on: model.zoom == .fit) { model.zoom = .fit }
                .tracking(0.8)
                .padding(.leading, 4)
                .help("Fit to width (⌘0)")
        }
        .fixedSize()
    }
}

private struct ZoomButton: View {
    var label: String
    var size: CGFloat = 11
    var on = false
    var action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        let hot = hovering && enabled
        Button(action: action) {
            Text(label)
                .font(Fonts.body(size))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .foregroundStyle(on ? Tone.accent : hot ? Tone.text : Tone.text55)
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(on ? Tone.accent : hot ? Tone.ruleStrong : .clear, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 }
    }
}
