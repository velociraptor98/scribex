import PDFKit
import ScribeXCore
import SwiftUI

/// ⌘E: choose the sheet and extras, then a save panel.
struct ExportSheet: View {
    let model: Session
    let pdf: Data
    let documentSheet: Sheet
    @State private var sheet: Sheet
    @State private var hyperlinks = false
    @State private var sourceAlongside = false
    @State private var thumbs: [NSImage] = []
    @State private var pages = 0
    @Environment(\.dismiss) private var dismiss

    init(model: Session, pdf: Data, documentSheet: Sheet) {
        self.model = model
        self.pdf = pdf
        self.documentSheet = documentSheet
        _sheet = State(initialValue: documentSheet)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export").font(Fonts.display(30))
                Text("\((model.name as NSString).deletingPathExtension).pdf" + (pages > 0 ? " · \(pages) page\(pages > 1 ? "s" : "")" : ""))
                    .italic().foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 24) {
                HStack(spacing: 8) {
                    ForEach(thumbs.indices, id: \.self) { i in
                        Image(nsImage: thumbs[i]).resizable().aspectRatio(contentMode: .fit).frame(height: 96).shadow(radius: 3, y: 2)
                    }
                }
                Form {
                    Picker("Sheet", selection: $sheet) {
                        ForEach(Sheet.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Hyperlinked cross-references", isOn: $hyperlinks)
                    Toggle("Save the source .tex alongside", isOn: $sourceAlongside)
                    if sheet != documentSheet {
                        Text("The document is set on \(documentSheet.label). Exporting re-typesets it on \(sheet.label); your file is not changed.")
                            .font(Fonts.text(11.5)).italic().foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack {
                Text(size + (model.buildMs.map { " · \($0) ms to set" } ?? "")).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.busy ? "Building…" : "Export PDF") {
                    dismiss()
                    model.export(ExportOptions(sheet: sheet, hyperlinks: hyperlinks, sourceAlongside: sourceAlongside))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.busy)
            }
        }
        .padding(24)
        .frame(width: 560)
        .scribeStyle()
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
            return page.thumbnail(of: NSSize(width: 192 * bounds.width / bounds.height, height: 192), for: .mediaBox)
        }
    }
}
