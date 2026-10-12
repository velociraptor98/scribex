import AppKit
import Observation
import ScribeXCore
import SwiftUI

/// One document window's model: the document and its editor, with its outline
/// and its typesetting, each kept up to date as the text changes. The file
/// itself, saving and the edited state belong to the document system; what the
/// window shows (panels, sheets, zoom) belongs to its views.
@Observable
public final class Session {

    let engine: Engine
    @ObservationIgnored let document: TexDocument
    let outline: Outline
    let typesetting: Typesetting
    public let editor = EditorHandle()

    /// The file on disk, once there is one.
    var fileURL: URL? {
        didSet { typesetting.fileURL = fileURL }
    }

    public init(document: TexDocument, engine: Engine) {
        self.document = document
        self.engine = engine
        outline = Outline(source: document.text)
        typesetting = Typesetting(document: document, engine: engine)
    }

    var source: String { document.text }
    var name: String { fileURL?.lastPathComponent ?? "untitled.tex" }

    // Shared state, reached through the session so views need only one model.
    var fetched: [String] { engine.fetched }
    func setUp() { engine.setUp() }

    // MARK: Editing

    /// The editor owns the text while the user types and reports each change.
    func edit(_ text: String) {
        document.text = text
        outline.update(text)
        typesetting.scheduleBuild()
    }

    func insert(_ text: String) {
        // "Turn the selection into a table" is the one suggestion whose output
        // depends on what is selected, so it is built here rather than in the
        // catalogue.
        let selection = editor.selectedText
        if text.isEmpty && !selection.isEmpty {
            guard let table = selectionToTable(selection) else {
                typesetting.status = "That selection is not rows of separated values"
                return
            }
            editor.insert(table)
            return
        }
        editor.insert(text)
    }

    func applyFix(_ fix: Fix) {
        editor.replaceOnLine(fix.line, find: fix.find, replace: fix.replace)
        typesetting.status = fix.label
    }

    func revealFolder() {
        guard let fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}

#if DEBUG
extension Session {
    /// A window's worth of state for previews: the article template, and any
    /// issues to show. Nothing is typeset.
    static func preview(issues: [Diagnostic] = []) -> Session {
        let session = Session(document: TexDocument(), engine: .preview)
        session.typesetting.showForPreview(issues)
        return session
    }
}

extension Engine {
    static let preview = Engine(worker: URL(filePath: "/usr/bin/false"))
}
#endif

