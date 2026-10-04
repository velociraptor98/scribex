import ScribeXCore
import SwiftUI

struct MarksView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let diags = model.visible
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Issues in this build").rubric().padding(.bottom, 18)

                ForEach(diags) { d in
                    MarkRow(diagnostic: d)
                }

                Text(diags.isEmpty
                    ? model.preview != nil ? "No issues — the document built cleanly." : "Nothing built yet."
                    : "Everything else built cleanly.")
                    .font(Fonts.body(11.5, italic: true))
                    .foregroundStyle(Tone.text42)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Hairline(color: Tone.rule10) }
            }
        }
        .scrollIndicators(.automatic)
    }
}

private struct MarkRow: View {
    @Environment(AppModel.self) private var model
    var diagnostic: Diagnostic

    var body: some View {
        let d = diagnostic
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(d.line.map { "l. \($0)" } ?? "—") {
                if let line = d.line { model.editor.goto(line) }
            }
            .buttonStyle(HoverButtonStyle(color: d.line == nil ? Tone.text38 : Tone.accent, hover: Tone.accent300))
            .font(Fonts.body(11))
            .monospacedDigit()
            .disabled(d.line == nil)
            .help(d.line.map { "Go to line \($0)" } ?? "")

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text(d.title)
                        .font(Fonts.heading(16, .semibold))
                        .foregroundStyle(Tone.text)
                    if d.severity == .error {
                        Circle().fill(Tone.mark).frame(width: 5, height: 5)
                    }
                }
                if let detail = d.detail {
                    Text(detail)
                        .font(Fonts.body(12))
                        .lineSpacing(12 * 0.65 - 4)
                        .foregroundStyle(Tone.text60)
                        .padding(.top, 5)
                }
                // TeX's own wording, for anything the translation flattened.
                if d.detail != nil, d.raw != d.title {
                    Text(d.raw)
                        .font(Fonts.mono(11))
                        .foregroundStyle(Tone.text38)
                        .textSelection(.enabled)
                        .padding(.top, 7)
                        .help("What TeX said")
                }
                HStack(spacing: 9) {
                    ForEach(d.fixes, id: \.self) { fix in
                        Button(fix.label) { model.applyFix(fix) }
                            .buttonStyle(InkButtonStyle(primary: true, size: .small))
                    }
                    Button("Ignore") { model.ignore(d) }
                        .buttonStyle(InkButtonStyle(size: .small))
                }
                .padding(.top, 11)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Hairline(color: Tone.accent.opacity(0.35)) }
    }
}

struct PressLogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Button { model.pressOpen.toggle() } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Press log").rubric()
                    Spacer()
                    HStack(spacing: 10) {
                        Text("Tectonic" + (model.buildMs.map { " · " + String(format: "%.2f s", Double($0) / 1000) } ?? ""))
                            .monospacedDigit()
                        Text(model.pressOpen ? "▾" : "▸").foregroundStyle(Tone.text38)
                    }
                    .font(Fonts.body(11.5))
                    .foregroundStyle(Tone.text42)
                }
                .padding(.horizontal, 26)
                .padding(.top, 12)
                .padding(.bottom, model.pressOpen ? 8 : 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if model.pressOpen {
                VStack(spacing: 0) {
                    let rows = model.press.isEmpty ? [PressRow(stage: "—", detail: "no run yet")] : model.press
                    ForEach(rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(row.stage).frame(width: 170, alignment: .leading)
                            Text(row.detail)
                                .foregroundStyle(row.flagged ? Tone.accent : model.press.isEmpty ? Tone.text38 : Tone.text62)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .overlay(alignment: .top) { Hairline(color: Tone.ruleSoft) }
                    }
                }
                .font(Fonts.mono(12))
                .monospacedDigit()
                .foregroundStyle(Tone.text62)
                .textSelection(.enabled)
                .padding(.horizontal, 26)
                .padding(.bottom, 16)
            }
        }
        .background(Tone.inkRaised)
        .overlay(alignment: .top) { Hairline() }
    }
}
