import Foundation

/// The only place the user's document is modified; builds never touch it.
public func saveDocument(_ source: String, to url: URL) throws(FileError) {
    let dir = url.deletingLastPathComponent()
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
        throw FileError("cannot create \(dir.path): \(error.localizedDescription)")
    }
    do {
        // Written in place rather than atomically: a rename would
        // replace a symlinked or hard-linked document instead of updating it.
        try Data(source.utf8).write(to: url)
    } catch {
        throw FileError("cannot save \(url.path): \(error.localizedDescription)")
    }
}

public func exportPDF(for entry: URL, to destination: URL) throws(FileError) -> Int {
    let src = Typesetter.pdfURL(for: entry)
    guard let data = FileManager.default.contents(atPath: src.path) else {
        throw FileError("nothing to export yet — build the document first")
    }
    do {
        try data.write(to: destination)
    } catch {
        throw FileError("cannot write \(destination.path): \(error.localizedDescription)")
    }
    return data.count
}

public struct FileError: Error, Sendable, CustomStringConvertible {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}
