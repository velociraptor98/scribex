import Foundation

/// A starter document. The list is Resources/Templates/templates.json and each
/// source is a .tex file beside it, so they read and edit as plain LaTeX. The
/// first-run download builds every one, so each works offline.
public struct Template: Hashable, Sendable, Identifiable {
    public var name: String
    public var note: String
    public var source: String

    public var id: String { name }
}

public let templates: [Template] = {
    struct Entry: Decodable { var name, note, file: String }
    let entries: [Entry] = bundled("Templates/templates.json")
    return entries.map { entry in
        Template(name: entry.name, note: entry.note,
                 source: try! String(contentsOf: bundledURL("Templates/" + entry.file), encoding: .utf8))
    }
}()

/// What a new document starts as.
public var articleSource: String { templates[0].source }
