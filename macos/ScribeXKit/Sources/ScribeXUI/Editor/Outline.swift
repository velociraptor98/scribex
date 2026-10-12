import Observation
import ScribeXCore

/// The document's headings and counts, for the sidebar: worked out again
/// shortly after typing pauses, since they barely change mid-word.
@Observable
final class Outline {
    private(set) var sections: [OutlineEntry]
    private(set) var tally: DocStats
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(source: String) {
        sections = outline(source)
        tally = stats(source)
    }

    func update(_ source: String) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            sections = outline(source)
            tally = stats(source)
        }
    }
}
