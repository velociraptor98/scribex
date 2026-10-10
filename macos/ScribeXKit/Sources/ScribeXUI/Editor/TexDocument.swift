import ScribeXCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in the app's Info.plist as an imported type, so a .tex file has
    /// a real type even on a Mac where nothing else has registered one.
    nonisolated public static let tex = UTType(importedAs: "org.tug.tex", conformingTo: .plainText)
}

/// A .tex file. The document system (DocumentGroup and NSDocument underneath)
/// owns opening, saving, autosave, versions, recents and the unsaved-changes
/// prompts; this type only converts between the file and its text.
///
/// A reference type, so that edits register on the document's undo manager
/// (see `Editor`) and that is what marks the window edited.
public nonisolated final class TexDocument: ReferenceFileDocument, @unchecked Sendable {
    public static let readableContentTypes: [UTType] = [.tex, .plainText]
    public static let writableContentTypes: [UTType] = [.tex]

    /// Read and written on the main actor only: by the editor as you type, and
    /// by the document system when it takes a snapshot to save.
    public var text: String

    public init(text: String = articleSource) {
        self.text = text
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        self.text = text
    }

    public func snapshot(contentType: UTType) throws -> String {
        text
    }

    public func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }
}
