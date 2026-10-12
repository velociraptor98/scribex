import PDFKit
import ScribeXCore
import SwiftUI
import UniformTypeIdentifiers

/// ⌘E: choose the sheet and extras, then the system's save panel.
struct ExportSheet: View {
    let model: Session
    let pdf: Data
    let documentSheet: Sheet
    @State private var sheet: Sheet
    @State private var hyperlinks = false
    @State private var sourceAlongside = false
    @State private var thumbs: [NSImage] = []
    @State private var pages = 0
    /// The PDF, once built, for the save panel.
    @State private var file: PDFFile?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    init(model: Session, pdf: Data, documentSheet: Sheet) {
        self.model = model
        self.pdf = pdf
        self.documentSheet = documentSheet
        _sheet = State(initialValue: documentSheet)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export").font(Fonts.display(30))
                    Text(summary).italic().foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Picker("Sheet", selection: $sheet) {
                    ForEach(Sheet.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            // The first pages, in tiles like the templates on Home.
            HStack(spacing: 12) {
                ForEach(thumbs.indices, id: \.self) { i in
                    VStack(spacing: 8) {
                        Image(nsImage: thumbs[i]).resizable().aspectRatio(contentMode: .fit)
                            .frame(height: 112).shadow(radius: 3, y: 2)
                            .frame(maxWidth: .infinity, minHeight: 136)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))
                        Text("Page \(i + 1)")
                    }
                }
            }
            // Always laid out, only hidden, so picking a sheet never resizes the panel.
            Text("The document is set on \(documentSheet.label). Exporting re-typesets it on \(sheet.label); your file is not changed.")
                .font(Fonts.text(11.5)).italic().foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(sheet == documentSheet ? 0 : 1)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Hyperlinked cross-references", isOn: $hyperlinks)
                    Toggle("Save the source .tex alongside", isOn: $sourceAlongside)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.typesetting.busy ? "Building…" : "Export PDF") {
                    Task {
                        guard let pdf = await model.typesetting.exportPDF(options) else { return }
                        file = PDFFile(data: pdf)
                        saving = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.typesetting.busy)
            }
            .buttonBorderShape(.capsule)
        }
        .padding(24)
        .frame(width: 560)
        .scribeStyle()
        .task(id: pdf) { renderThumbnails() }
        // Cancelling the panel leaves the sheet open, to change the options.
        .fileExporter(isPresented: $saving, document: file, contentType: .pdf,
                      defaultFilename: (model.name as NSString).deletingPathExtension) { result in
            switch result {
            case let .success(url): if let file { model.typesetting.exported(file.data, to: url, sourceAlongside: sourceAlongside) }
            case let .failure(error): model.typesetting.status = "Export failed: \(error.localizedDescription)"
            }
            dismiss()
        }
    }

    private var options: ExportOptions {
        ExportOptions(sheet: sheet, hyperlinks: hyperlinks, sourceAlongside: sourceAlongside)
    }

    /// "good.pdf · 2 pages · 41 KB"
    private var summary: String {
        let name = (model.name as NSString).deletingPathExtension + ".pdf"
        let count = pages > 0 ? " · \(pages) page\(pages > 1 ? "s" : "")" : ""
        return name + count + " · " + size
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

/// The exported PDF, in the form the save panel writes.
private struct PDFFile: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    // A blank A4 page, so the thumbnail and size show as they would.
    let page = PDFPage()
    page.setBounds(CGRect(x: 0, y: 0, width: 595, height: 842), for: .mediaBox)
    let pdf = PDFDocument()
    pdf.insert(page, at: 0)
    return ExportSheet(model: .preview(), pdf: pdf.dataRepresentation() ?? Data(), documentSheet: .a4)
}
