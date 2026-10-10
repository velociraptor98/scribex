import ScribeXCore
import SwiftUI

/// A drawer over the foot of the preview: one line with the count and the
/// build's status, which opens upward into what TeX complained about, in plain words, with fixes.
/// It lies on top of the pages rather than beside them, so opening it never
/// resizes the PDF.
struct Issues: View {
    let model: Session
    @Binding var isExpanded: Bool

    var body: some View {
        let diags = model.visible
        VStack(spacing: 0) {
            if isExpanded {
                list(diags)
                Divider()
            }
            Button { isExpanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    Text(summary(diags)).smallCaps()
                    Spacer()
                    // Warnings still build, so the outcome is not implied by the count.
                    Text(model.status)
                        .font(Fonts.text(11.5)).foregroundStyle(.secondary).monospacedDigit()
                        .lineLimit(1).truncationMode(.tail)
                        .opacity(model.busy ? 0.6 : 1)
                        .help(model.status)
                }
                .padding(.horizontal, 16)
                .frame(height: 34)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide the issues (⇧⌘M)" : "Show the issues (⇧⌘M)")
        }
        .background(.canvas)
        .overlay(alignment: .top) { Divider() }
        .shadow(color: .black.opacity(isExpanded ? 0.3 : 0), radius: 12, y: -4)
    }

    private func summary(_ diags: [Diagnostic]) -> String {
        switch diags.count {
        case 0: "No issues"
        case 1: "1 issue"
        case let n: "\(n) issues"
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
            .padding(16)
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
