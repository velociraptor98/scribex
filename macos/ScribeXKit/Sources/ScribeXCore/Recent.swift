import Foundation

public func documentTitle(_ source: String, path: String?) -> String {
    if let m = source.firstMatch(of: #/\\title\s*\{([^}]+)\}/#) {
        let title = m.1.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
    }
    return path.map { ($0 as NSString).lastPathComponent } ?? "untitled.tex"
}

public func when(_ date: Date, now: Date = .now) -> String {
    let mins = Int(now.timeIntervalSince(date) / 60)
    if mins < 1 { return "Just now" }
    if mins < 60 { return "\(mins) min ago" }
    let hours = mins / 60
    if hours < 24 { return "\(hours) hour\(hours > 1 ? "s" : "") ago" }
    if hours / 24 == 1 { return "Yesterday" }
    return date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_GB")))
}
