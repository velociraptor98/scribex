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

/// Bundled with the app, so files that fail to load are a build mistake.
public let templates: [Template] = {
    struct Entry: Decodable { var name, note, file: String }
    let folder = Bundle.module.url(forResource: "Templates", withExtension: nil, subdirectory: "Resources")!
    let entries = try! JSONDecoder().decode([Entry].self, from: Data(contentsOf: folder.appending(path: "templates.json")))
    return entries.map { entry in
        Template(name: entry.name, note: entry.note,
              source: try! String(contentsOf: folder.appending(path: entry.file), encoding: .utf8))
    }
}()

/// What a new document starts as.
public var articleSource: String { templates[0].source }
