import PDFKit
import ScribeXCore
import SwiftUI

struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    let pdf: Data
    @State private var sheet: Sheet
    @State private var hyperlinks = false
    @State private var sourceAlongside = false
    @State private var thumbs: [NSImage] = []
    @State private var pages = 0

    private let documentSheet: Sheet

    init(pdf: Data, documentSheet: Sheet) {
        self.pdf = pdf
        self.documentSheet = documentSheet
        _sheet = State(initialValue: documentSheet)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Tone.scrim
                    .contentShape(Rectangle())
                    .onTapGesture { model.exportOpen = false }

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Export").font(Fonts.heading(30)).foregroundStyle(Tone.text)
                        Text("\((model.name as NSString).deletingPathExtension).pdf"
                            + (pages > 0 ? " · \(pages) page\(pages > 1 ? "s" : "")" : ""))
                            .font(Fonts.body(12.5, italic: true))
                            .foregroundStyle(Tone.text55)
                    }
                    .padding(.top, 26)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 22)

                    Hairline()

                    HStack(alignment: .top, spacing: 26) {
                        HStack(spacing: 9) {
                            ForEach(Array(thumbs.enumerated()), id: \.offset) { _, image in
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 88)
                                    .border(Tone.plateEdge, width: 4)
                            }
                            if thumbs.isEmpty {
                                Tone.paper.frame(width: 66, height: 88).border(Tone.plateEdge, width: 4)
                            }
                        }
                        .fixedSize()

                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Sheet").rubric(Tone.text42, tracking: 0.16)
                                Segmented(selection: $sheet)
                            }
                            VStack(alignment: .leading, spacing: 9) {
                                Check(on: $hyperlinks, label: "Hyperlinked cross-references")
                                Check(on: $sourceAlongside, label: "Save the source .tex alongside")
                            }
                            if sheet != documentSheet {
                                Text("The document is set on \(documentSheet.label). Exporting will re-typeset it on \(sheet.label); your file is not changed.")
                                    .font(Fonts.body(11.5, italic: true))
                                    .foregroundStyle(Tone.text42)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, 28)

                    HStack(spacing: 16) {
                        Text(size + (model.buildMs.map { " · \($0) ms to set" } ?? ""))
                            .monospacedDigit()
                        Spacer()
                        Button("Cancel") { model.exportOpen = false }
                            .buttonStyle(InkButtonStyle())
                            .keyboardShortcut(.cancelAction)
                        Button(model.busy ? "Building…" : "Export PDF") {
                            model.export(ExportOptions(sheet: sheet, hyperlinks: hyperlinks, sourceAlongside: sourceAlongside))
                        }
                        .buttonStyle(InkButtonStyle(primary: true))
                        .disabled(model.busy)
                        .keyboardShortcut(.defaultAction)
                    }
                    .font(Fonts.body(11.5))
                    .foregroundStyle(Tone.text42)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 28)
                    .background(Tone.inkRaised)
                    .overlay(alignment: .top) { Hairline(color: Tone.rule14) }
                }
                .frame(width: min(560, geo.size.width - 48))
                .background(Tone.inkPanel)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Tone.text.opacity(0.18), lineWidth: 1) }
                .shadow(color: .black.opacity(0.6), radius: 30, y: 24)
            }
        }
        .task(id: pdf) { renderThumbnails() }
    }

    /// Most PDFs here are tens of kilobytes; "0.02 MB" tells the reader nothing.
    private var size: String {
        pdf.count < 1024 * 1024
            ? "\(Int((Double(pdf.count) / 1024).rounded())) KB"
            : String(format: "%.1f MB", Double(pdf.count) / 1024 / 1024)
    }

    /// A fixed height, so Letter and A5 stack to the same measure.
    private func renderThumbnails() {
        guard let document = PDFDocument(data: pdf) else { return }
        pages = document.pageCount
        thumbs = (0..<min(2, document.pageCount)).compactMap { i in
            guard let page = document.page(at: i) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let height: CGFloat = 176
            return page.thumbnail(of: NSSize(width: height * bounds.width / bounds.height, height: height), for: .mediaBox)
        }
    }
}

private struct Segmented: View {
    @Binding var selection: Sheet

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Sheet.allCases.enumerated()), id: \.element) { i, sheet in
                if i > 0 { Hairline(color: Tone.ruleStrong, vertical: true) }
                SegmentButton(label: sheet.label, on: selection == sheet) { selection = sheet }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Tone.ruleStrong, lineWidth: 1) }
    }
}

private struct SegmentButton: View {
    var label: String
    var on: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Fonts.heading(12.5, .semibold))
                .foregroundStyle(on ? Tone.accent : Tone.text70)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(on ? Tone.accent.opacity(0.14) : hovering ? Tone.text.opacity(0.06) : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct Check: View {
    @Binding var on: Bool
    var label: String

    var body: some View {
        Button { on.toggle() } label: {
            HStack(spacing: 9) {
                Text(on ? "✓" : "")
                    .font(Fonts.mono(9))
                    .foregroundStyle(Tone.accent)
                    .frame(width: 13, height: 13)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(on ? Tone.accent : Tone.text.opacity(0.28), lineWidth: 1)
                    }
                Text(label)
                    .font(Fonts.body(12.5))
                    .foregroundStyle(on ? Tone.text.opacity(0.8) : Tone.text50)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(on ? "on" : "off")
    }
}
