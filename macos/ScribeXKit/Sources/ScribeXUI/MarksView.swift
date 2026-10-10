import ScribeXCore
import SwiftUI

/// The Issues tab: what TeX complained about, in plain words, with fixes.
struct MarksView: View {
    @Environment(Session.self) private var model

    var body: some View {
        let diags = model.visible
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(diags) { d in
                    MarkRow(diagnostic: d)
                    Divider()
                }
                Text(diags.isEmpty
                    ? model.preview != nil ? "No issues — the document built cleanly." : "Nothing built yet."
                    : "Everything else built cleanly.")
                    .italic().foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MarkRow: View {
    @Environment(Session.self) private var model
    let diagnostic: Diagnostic

    var body: some View {
        let d = diagnostic
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(d.line.map { "l. \($0)" } ?? "—") {
                if let line = d.line { model.editor.goto(line) }
            }
            .buttonStyle(.link)
            .disabled(d.line == nil)
            .help(d.line.map { "Go to line \($0)" } ?? "")
            .frame(minWidth: 36, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(d.title).font(Fonts.display(17, .semibold))
                } icon: {
                    if d.severity == .error { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.mark) }
                }
                if let detail = d.detail {
                    Text(detail).foregroundStyle(.secondary)
                }
                // TeX's own wording, for anything the translation flattened.
                if d.detail != nil, d.raw != d.title {
                    Text(d.raw).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary).textSelection(.enabled)
                }
                HStack {
                    ForEach(d.fixes, id: \.self) { fix in
                        Button(fix.label) { model.applyFix(fix) }.buttonStyle(.borderedProminent)
                    }
                    Button("Ignore") { model.ignore(d) }
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The strip along the window's foot: the last build in one line, opening
/// into TeX's passes.
struct PressLogView: View {
    @Environment(Session.self) private var model

    var body: some View {
        @Bindable var model = model
        DisclosureGroup(isExpanded: $model.pressOpen) {
            let rows = model.press.isEmpty ? [PressRow(stage: "—", detail: "no run yet")] : model.press
            Grid(alignment: .leading, verticalSpacing: 4) {
                ForEach(rows) { row in
                    GridRow {
                        Text(row.stage)
                        Text(row.detail).foregroundStyle(row.flagged ? AnyShapeStyle(.gilt) : AnyShapeStyle(.secondary))
                    }
                }
            }
            .font(.system(size: 11.5, design: .monospaced))
            .textSelection(.enabled)
            .padding(.top, 8)
        } label: {
            HStack {
                Text("Press log").smallCaps()
                Spacer()
                Text("Tectonic" + (model.buildMs.map { " · " + String(format: "%.2f s", Double($0) / 1000) } ?? ""))
                    .font(Fonts.text(11.5)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
