// Tectonic never runs in the app's process (see engine/src/engine.rs): each
// build launches the `scribex-typeset` worker and speaks the protocol in
// engine/src/worker.rs.

import Foundation

public struct Build: Sendable {
    public var pdf: Data
    public var log: String
    public var durationMs: Int
}

public struct BuildError: Error, Sendable {
    public var message: String
    public var log: String
    /// A resource absent from the offline cache, which a download can supply.
    public var missingFile: String?
    /// A file the bundle lacks too, such as a class or image the document
    /// expects beside it.
    public var absentFile: String?
    public var durationMs: Int
    /// A newer build replaced this one before it ran. Not a failure to report.
    public var superseded: Bool

    public init(
        _ message: String, log: String = "", missingFile: String? = nil,
        absentFile: String? = nil, durationMs: Int = 0, superseded: Bool = false
    ) {
        self.message = message
        self.log = log
        self.missingFile = missingFile
        self.absentFile = absentFile
        self.durationMs = durationMs
        self.superseded = superseded
    }

    static let supersededByNewer = BuildError("superseded by a newer build", superseded: true)

    /// A build that failed because nothing has been downloaded yet: without the
    /// format file the engine cannot even start, so the log says nothing useful.
    public var isColdCache: Bool { message.contains("tectonic-format-") }
}

/// Jobs run one at a time. Every build for a document writes the same
/// `.scribex-build` directory, so two workers at once interleave their
/// `.aux`/`.log`/`.pdf` writes: multi-pass documents stop converging, and we
/// could read back the *other* run's PDF. Live preview makes overlap the norm,
/// since a compile outlasts the 600 ms debounce.
///
/// Queued previews are dropped once a newer one exists, which keeps the editor
/// from falling a build behind after a burst of typing.
public actor Typesetter {
    /// Dropping is only safe when the job's output is all it was for. A job that
    /// fetches resources also fills the shared cache, which outlives the unwanted
    /// PDF, so priming the cache or an explicit "fetch it" always runs.
    public enum IfSuperseded: Sendable {
        case drop, run
    }

    /// Its absence makes the app offer the first-run download.
    static let readyMarker = "cache-ready"

    private let worker: URL
    private var latest: UInt64 = 0
    /// Held for the whole job, PDF read included, so the bytes we return are the
    /// ones our own worker wrote.
    private var running = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init(worker: URL) {
        self.worker = worker
        // A worker that dies before reading its request would otherwise take the
        // app down with it: writing to its closed stdin raises SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
    }

    public static func outputDirectory(for entry: URL) -> URL {
        entry.deletingLastPathComponent().appending(path: ".scribex-build", directoryHint: .isDirectory)
    }

    public static func pdfURL(for entry: URL) -> URL {
        outputDirectory(for: entry).appending(path: entry.deletingPathExtension().lastPathComponent + ".pdf")
    }

    /// The file at `entry` is neither read nor written; its directory is where
    /// `\input` and `\includegraphics` resolve. `onFetch` is called on a
    /// background thread.
    public func typeset(
        entry: URL,
        source: String,
        onlyCached: Bool,
        ifSuperseded: IfSuperseded = .drop,
        onFetch: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws(BuildError) -> Build {
        // Claimed even by jobs that will not drop themselves, so that they still
        // supersede the previews queued ahead of them.
        latest += 1
        let ticket = latest
        await acquire()
        defer { release() }
        if ifSuperseded == .drop, latest > ticket {
            throw .supersededByNewer
        }

        let request = WorkerRequest(
            entry: entry.path,
            source: source,
            outDir: Self.outputDirectory(for: entry).path,
            onlyCached: onlyCached
        )
        switch await Self.run(worker, request, onFetch: onFetch) {
        case let .ok(log, durationMs):
            do {
                let pdf = try Data(contentsOf: Self.pdfURL(for: entry))
                return Build(pdf: pdf, log: log, durationMs: durationMs)
            } catch {
                throw BuildError("no PDF produced: \(error.localizedDescription)", log: log, durationMs: durationMs)
            }
        case let .err(message, log, missingFile, absentFile, durationMs):
            throw BuildError(message, log: log, missingFile: missingFile, absentFile: absentFile, durationMs: durationMs)
        }
    }

    /// A marker rather than a probe build, which takes seconds to fail on an
    /// empty cache. A cache cleared later is caught by `BuildError.isColdCache`.
    public nonisolated static func cacheReady(in dataDirectory: URL) -> Bool {
        FileManager.default.fileExists(atPath: dataDirectory.appending(path: readyMarker).path)
    }

    /// Returns milliseconds taken. An interrupted run can be retried: what
    /// arrived stays cached.
    public func warmUp(
        documents: [String],
        dataDirectory: URL,
        onFetch: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws(BuildError) -> Int {
        let started = ContinuousClock.now
        let work = dataDirectory.appending(path: "warmup", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        } catch {
            throw BuildError("cannot stage warmup: \(error.localizedDescription)")
        }

        let jobs = [try await Self.warmupDocument(worker)] + documents
        for (i, source) in jobs.enumerated() {
            // Never dropped as superseded: the cache write is the point.
            _ = try await typeset(
                entry: work.appending(path: "warmup-\(i).tex"),
                source: source,
                onlyCached: false,
                ifSuperseded: .run,
                onFetch: onFetch
            )
        }

        do {
            try Data().write(to: dataDirectory.appending(path: Self.readyMarker))
        } catch {
            throw BuildError("cannot record setup: \(error.localizedDescription)")
        }
        return Int((ContinuousClock.now - started) / .milliseconds(1))
    }

    private func acquire() async {
        if !running {
            running = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            running = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}

struct WorkerRequest: Encodable {
    var entry: String
    var source: String
    var outDir: String
    var onlyCached: Bool

    enum CodingKeys: String, CodingKey {
        case entry, source
        case outDir = "out_dir"
        case onlyCached = "only_cached"
    }
}

enum WorkerResponse: Decodable {
    case ok(log: String, durationMs: Int)
    case err(message: String, log: String, missingFile: String?, absentFile: String?, durationMs: Int)

    enum CodingKeys: String, CodingKey {
        case status, log, message
        case durationMs = "duration_ms"
        case missingFile = "missing_file"
        case absentFile = "absent_file"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let log = try c.decode(String.self, forKey: .log)
        let durationMs = try c.decode(Int.self, forKey: .durationMs)
        switch try c.decode(String.self, forKey: .status) {
        case "ok":
            self = .ok(log: log, durationMs: durationMs)
        default:
            self = .err(
                message: try c.decode(String.self, forKey: .message),
                log: log,
                missingFile: try c.decodeIfPresent(String.self, forKey: .missingFile),
                absentFile: try c.decodeIfPresent(String.self, forKey: .absentFile),
                durationMs: durationMs
            )
        }
    }

    static func failure(_ message: String) -> Self {
        .err(message: message, log: "", missingFile: nil, absentFile: nil, durationMs: 0)
    }
}

private let fetchPrefix = "scribex-fetch\t"

extension Typesetter {
    static func run(
        _ worker: URL, _ request: WorkerRequest, onFetch: @escaping @Sendable (String) -> Void
    ) async -> WorkerResponse {
        await withCheckedContinuation { done in
            DispatchQueue.global(qos: .userInitiated).async {
                done.resume(returning: runBlocking(worker, request, onFetch: onFetch))
            }
        }
    }

    private static func runBlocking(
        _ worker: URL, _ request: WorkerRequest, onFetch: @escaping @Sendable (String) -> Void
    ) -> WorkerResponse {
        let process = Process()
        process.executableURL = worker
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return .failure("cannot start worker: \(error.localizedDescription)")
        }

        // Drained on its own thread so progress arrives while the job runs, and
        // so a chatty engine can never block on a full pipe.
        let progress = DispatchGroup()
        DispatchQueue.global(qos: .utility).async(group: progress) {
            forEachLine(of: stderr.fileHandleForReading) { line in
                if line.hasPrefix(fetchPrefix) { onFetch(String(line.dropFirst(fetchPrefix.count))) }
            }
        }

        do {
            try stdin.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(request))
            // Closing stdin signals end-of-request to the worker.
            try stdin.fileHandleForWriting.close()
        } catch {
            process.terminate()
            return .failure("cannot send job: \(error.localizedDescription)")
        }

        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        progress.wait()

        if out.isEmpty {
            // The engine aborted or was killed: what the worker process is for.
            let status = process.terminationReason == .uncaughtSignal
                ? "signal: \(process.terminationStatus)"
                : "exit status: \(process.terminationStatus)"
            return .failure(
                "the typesetting engine crashed (\(status)). Your document is safe; "
                    + "please report this with the source that triggered it."
            )
        }

        do {
            return try JSONDecoder().decode(WorkerResponse.self, from: out)
        } catch {
            return .failure("malformed worker response: \(error.localizedDescription)")
        }
    }

    private static func forEachLine(of handle: FileHandle, _ body: (String) -> Void) {
        var buffer = Data()
        while true {
            // Blocks until there is output; empty means the worker closed stderr.
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                body(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
        }
    }

    static func warmupDocument(_ worker: URL) async throws(BuildError) -> String {
        let result: Result<String, BuildError> = await withCheckedContinuation { done in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = worker
                process.arguments = ["--warmup-document"]
                let stdout = Pipe()
                process.standardOutput = stdout
                do {
                    try process.run()
                } catch {
                    return done.resume(returning: .failure(BuildError("cannot start worker: \(error.localizedDescription)")))
                }
                let out = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                done.resume(returning: out.isEmpty
                    ? .failure(BuildError("the worker has no warmup document"))
                    : .success(String(decoding: out, as: UTF8.self)))
            }
        }
        return try result.get()
    }
}
