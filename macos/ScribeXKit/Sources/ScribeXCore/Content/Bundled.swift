import Foundation

/// A file shipped in Resources/, by its path there ("Templates/article.tex").
/// These are part of the build, so a missing or malformed one is a programming
/// error, not something to recover from.
func bundledURL(_ path: String) -> URL {
    let folder = ("Resources/" + path as NSString).deletingLastPathComponent
    return Bundle.module.url(forResource: (path as NSString).lastPathComponent, withExtension: nil, subdirectory: folder)!
}

/// A JSON file shipped in Resources/, decoded.
func bundled<T: Decodable>(_ path: String) -> T {
    try! JSONDecoder().decode(T.self, from: Data(contentsOf: bundledURL(path)))
}
