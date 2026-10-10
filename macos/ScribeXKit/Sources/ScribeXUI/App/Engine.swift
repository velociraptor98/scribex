import Foundation
import Observation
import ScribeXCore

/// What every window shares: the typesetter and the download cache it reads.
/// One per app.
@Observable
public final class Engine {
    public enum CacheState { case unknown, cold, downloading, failed, ready }

    public struct SetupProgress {
        var files = 0
        var current: String?
        var error: String?
    }

    private(set) var cache = CacheState.unknown
    private(set) var setup = SetupProgress()
    /// Packages and fonts arriving right now, for the title bar.
    private(set) var fetched: [String] = []

    @ObservationIgnored let typesetter: Typesetter
    @ObservationIgnored let dataDirectory: URL
    @ObservationIgnored private var settingUp = false

    /// Nothing can be built, so nothing can be opened, until the cache exists.
    var locked: Bool { cache != .ready }

    public init(worker: URL) {
        typesetter = Typesetter(worker: worker)
        dataDirectory = URL.applicationSupportDirectory.appending(path: "com.kunalsingh.scribex", directoryHint: .isDirectory)
        cache = Typesetter.cacheReady(in: dataDirectory) ? .ready : .cold
    }

    /// The worker sits beside the app's executable; SCRIBEX_WORKER points at one
    /// outside a bundle, for development.
    public static var bundledWorker: URL {
        if let path = ProcessInfo.processInfo.environment["SCRIBEX_WORKER"] {
            return URL(filePath: path)
        }
        return Bundle.main.url(forAuxiliaryExecutable: "scribex-typeset")
            ?? Bundle.main.bundleURL.appending(path: "Contents/MacOS/scribex-typeset")
    }

    /// Where an untitled document builds: its own folder, so two untitled
    /// windows never share a build directory.
    func scratchEntry() -> URL {
        dataDirectory.appending(path: "scratch/\(UUID().uuidString)/untitled.tex")
    }

    var fetchHandler: @Sendable (String) -> Void {
        { [weak self] name in
            Task { @MainActor in self?.noteFetch(name) }
        }
    }

    func clearFetched() {
        fetched = []
    }

    private func noteFetch(_ name: String) {
        fetched.append(name)
        if settingUp {
            setup.files += 1
            setup.current = name
        }
    }

    /// Downloads the core packages and fonts by building every template once.
    /// Windows watch `cache` and rebuild when it turns ready.
    func setUp() {
        guard !settingUp else { return }
        settingUp = true
        cache = .downloading
        setup = SetupProgress()
        Task {
            defer {
                settingUp = false
                fetched = []
            }
            do throws(BuildError) {
                _ = try await typesetter.warmUp(
                    documents: templates.map(\.source),
                    dataDirectory: dataDirectory,
                    onFetch: fetchHandler
                )
                cache = .ready
            } catch {
                // Priming is never dropped as superseded, so anything caught here is real.
                cache = .failed
                setup.error = error.message
            }
        }
    }

    /// A build found the cache missing (cleared since setup ran, say).
    func noteColdCache() {
        if cache != .downloading && cache != .failed { cache = .cold }
    }
}

#if DEBUG
extension Engine {
    /// An engine held in one setup state, for previews.
    static func preview(_ cache: CacheState, files: Int = 0, error: String? = nil) -> Engine {
        let engine = Engine(worker: URL(filePath: "/usr/bin/false"))
        engine.cache = cache
        engine.setup = SetupProgress(files: files, current: files > 0 ? "lmodern.sty" : nil, error: error)
        return engine
    }
}
#endif
