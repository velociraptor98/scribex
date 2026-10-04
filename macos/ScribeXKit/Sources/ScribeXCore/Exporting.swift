/*
 * Making the export sheet's options real.
 *
 * The engine copies whatever the last build produced, so an export option only
 * means something if it changes the document that gets built. Both options here
 * do that by rewriting the source for one throwaway build — the buffer on
 * screen and the file on disk are never touched.
 */

import Foundation

public enum Sheet: String, CaseIterable, Sendable, Identifiable {
    case letter, a4, a5

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .letter: "Letter"
        case .a4: "A4"
        case .a5: "A5"
        }
    }

    /// The class option that selects this paper size.
    public var option: String {
        switch self {
        case .letter: "letterpaper"
        case .a4: "a4paper"
        case .a5: "a5paper"
        }
    }
}

nonisolated(unsafe) private let paperOption = #/(?i)^(?:a[0-6]|b[0-6]|ansi[a-e]|letter|legal|executive)paper$/#
nonisolated(unsafe) private let documentClass = #/\\documentclass(\s*\[([^\]]*)\])?\s*\{([^}]+)\}/#

/// Set the paper size as a *class* option rather than a `geometry` one.
///
/// geometry reads the class option, so this works whether or not the document
/// loads geometry — and it cannot raise the option clash that a second
/// `\usepackage[a4paper]{geometry}` would in a document that already loads it.
public func withSheet(_ source: String, _ sheet: Sheet) -> String {
    guard let m = source.firstMatch(of: documentClass) else { return source }

    var opts = (m.2.map(String.init) ?? "")
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && $0.firstMatch(of: paperOption) == nil }
    opts.append(sheet.option)

    var out = source
    out.replaceSubrange(m.range, with: "\\documentclass[\(opts.joined(separator: ","))]{\(m.3)}")
    return out
}

/// Load hyperref, unless the document already does. Last in the preamble is
/// where it wants to be — it redefines a great deal on the way in.
public func withHyperref(_ source: String) -> String {
    if source.contains(#/\\usepackage(\[[^\]]*\])?\{[^}]*\bhyperref\b[^}]*\}/#) { return source }
    guard let at = source.range(of: "\\begin{document}") else { return source }
    var out = source
    out.insert(contentsOf: "\\usepackage{hyperref}\n", at: at.lowerBound)
    return out
}

public struct ExportOptions: Hashable, Sendable {
    public var sheet: Sheet
    public var hyperlinks: Bool
    /// Write the .tex next to the PDF.
    public var sourceAlongside: Bool

    public init(sheet: Sheet, hyperlinks: Bool = false, sourceAlongside: Bool = false) {
        self.sheet = sheet
        self.hyperlinks = hyperlinks
        self.sourceAlongside = sourceAlongside
    }

    public func needsRebuild(documentSheet: Sheet) -> Bool {
        sheet != documentSheet || hyperlinks
    }

    public func apply(to source: String) -> String {
        let out = withSheet(source, sheet)
        return hyperlinks ? withHyperref(out) : out
    }
}

/// The paper size the document already declares, so the sheet control opens on
/// the truth rather than on a guess.
public func sheetOf(_ source: String) -> Sheet {
    let opts = (source.firstMatch(of: documentClass)?.2.map(String.init) ?? "")
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    // article/report/book default to US Letter.
    return Sheet.allCases.first { opts.contains($0.option) } ?? .letter
}
