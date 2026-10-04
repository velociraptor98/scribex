import Foundation

public struct RecentDoc: Codable, Hashable, Sendable, Identifiable {
    public var path: String
    public var title: String
    public var sections: Int
    public var citations: Int
    public var opened: Date

    public var id: String { path }

    public init(path: String, title: String, sections: Int, citations: Int, opened: Date = .now) {
        self.path = path
        self.title = title
        self.sections = sections
        self.citations = citations
        self.opened = opened
    }
}

public struct RecentStore: Sendable {
    public static let key = "scribex.recent"
    public static let limit = 8

    private let suite: String?

    /// `suite` names a separate defaults domain, for tests.
    public init(suite: String? = nil) {
        self.suite = suite
    }

    private var defaults: UserDefaults {
        suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func load() -> [RecentDoc] {
        guard let data = defaults.data(forKey: Self.key),
              let docs = try? JSONDecoder().decode([RecentDoc].self, from: data)
        else { return [] }
        return Array(docs.sorted { $0.opened > $1.opened }.prefix(Self.limit))
    }

    @discardableResult
    public func remember(_ doc: RecentDoc) -> [RecentDoc] {
        var stamped = doc
        stamped.opened = .now
        let next = Array(([stamped] + load().filter { $0.path != doc.path }).prefix(Self.limit))
        // A full or disabled store costs us the list, not the document.
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.key)
        }
        return next
    }
}

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
