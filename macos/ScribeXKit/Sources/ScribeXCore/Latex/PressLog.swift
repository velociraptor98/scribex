import Foundation

// The press log: one line per stage of the last build, read from the log and
// the source. Shown in the strip along the foot of the window.

public struct PressRow: Hashable, Sendable, Identifiable {
    public var stage: String
    public var detail: String
    public var flagged: Bool

    public init(stage: String, detail: String, flagged: Bool = false) {
        self.stage = stage
        self.detail = detail
        self.flagged = flagged
    }

    public var id: String { stage }
}

nonisolated(unsafe) private let overfull = #/^(Over|Under)full \\[hv]box/#
nonisolated(unsafe) private let labelCall = #/\\label\s*\{[^}]+\}/#

private func plural(_ n: Int, _ word: String) -> String {
    "\(n) \(word)\(n > 1 ? "s" : "")"
}

/// Per-stage findings, not timings: Tectonic runs its passes internally and
/// reports only the total duration.
public func pressLog(
    _ log: String, source: String = "", name: String = "document.tex", diags: [Diagnostic] = []
) -> [PressRow] {
    let stem = name.replacing(#/(?i)\.tex$/#, with: "")
    var rows: [PressRow] = []

    rows.append(PressRow(stage: "typeset", detail: "\(name) → \(stem).pdf"))

    let cited = citedKeys(source)
    if !cited.isEmpty {
        let unresolved = diags.filter { $0.title.hasPrefix("No such reference") }.count
        rows.append(PressRow(
            stage: "bibliography",
            detail: unresolved > 0
                ? plural(unresolved, "unresolved key")
                : "\(plural(cited.count, "key")) resolved",
            flagged: unresolved > 0
        ))
    }

    let labelCount = source.matches(of: labelCall).count
    if labelCount > 0 {
        let dangling = diags.filter { $0.title.hasPrefix("No such label") }.count
        let rerun = log.contains("Label(s) may have changed")
        rows.append(PressRow(
            stage: "cross-refs",
            detail: rerun
                ? "labels moved — rebuilt to settle"
                : dangling > 0 ? "\(dangling) unresolved" : "\(plural(labelCount, "label")) resolved",
            flagged: dangling > 0
        ))
    }

    let overfullCount = log.components(separatedBy: "\n").filter { $0.firstMatch(of: overfull) != nil }.count
    if overfullCount > 0 {
        rows.append(PressRow(
            stage: "justification",
            detail: "\(plural(overfullCount, "line")) outside the measure",
            flagged: true
        ))
    }

    return rows
}
