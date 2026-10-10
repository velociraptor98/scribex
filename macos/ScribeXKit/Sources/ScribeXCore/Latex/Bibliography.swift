import Foundation

// Citations in the source and the entries in its .bib files, so a log error
// about an unknown key can suggest the nearest real one.

nonisolated(unsafe) private let citeKeys = #/\\(?:cite|citep|citet|citeauthor|citeyear|parencite|textcite)\s*(?:\[[^\]]*\])*\{([^}]*)\}/#

public func citedKeys(_ source: String) -> Set<String> {
    var keys = Set<String>()
    for m in source.matches(of: citeKeys) {
        for k in m.1.split(separator: ",", omittingEmptySubsequences: false) {
            let key = k.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { keys.insert(key) }
        }
    }
    return keys
}

public func bibKeys(_ bib: String) -> [String] {
    bib.matches(of: #/@\w+\s*\{\s*([^,\s}]+)/#).map { String($0.1) }
}

public func bibliographyFiles(_ source: String) -> [String] {
    source.matches(of: #/\\(?:bibliography|addbibresource)\s*\{([^}]+)\}/#)
        .flatMap { $0.1.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        .map { $0.hasSuffix(".bib") ? $0 : "\($0).bib" }
}
