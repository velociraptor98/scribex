import ScribeXCore
import SwiftUI

/// The panel under the preview: what TeX complained about, in
/// plain words, with fixes.
struct Issues: View {
    let model: Session

    var body: some View {
        let diags = model.visible
        VStack(spacing: 0) {
            HStack {
                Text(diags.isEmpty ? "Issues" : "Issues · \(diags.count)").smallCaps()
                Spacer()
                Button("Close", systemImage: "xmark") { model.issuesOpen = false }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .help("Hide the issues (⇧⌘M)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            list(diags)
        }
    }

    private func list(_ diags: [Diagnostic]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(diags) { d in
                    IssueRow(model: model, diagnostic: d)
                    Divider()
                }
                Text(diags.isEmpty
                    ? model.preview != nil ? "No issues — the document built cleanly." : "Nothing built yet."
                    : "Everything else built cleanly.")
                    .italic().foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct IssueRow: View {
    let model: Session
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

#Preview {
    let issue = Diagnostic(
        severity: .error, title: "Unknown command",
        detail: "TeX does not recognise this command. Check the spelling, or load the package that defines it.",
        raw: "Undefined control sequence.", line: 12,
        fixes: [Fix(label: "Use \\emph", line: 12, find: "\\emhp", replace: "\\emph")]
    )
    Issues(model: .preview(issues: [issue])).scribeStyle().frame(width: 900, height: 260)
}
