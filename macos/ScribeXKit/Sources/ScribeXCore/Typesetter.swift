// Tectonic never runs in the app's process (see engine/src/engine.rs): each
// build launches the `scribex-typeset` worker and speaks the protocol in
// engine/src/worker.rs.

import Foundation
import Synchronization

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
    /// Dropped or stopped for a newer build of the same document, or because
    /// its caller cancelled it. Not a failure to report.
    public var superseded: Bool
    /// Stopped for running too long: most likely a document that loops forever.
    public var timedOut: Bool

    public init(
        _ message: String, log: String = "", missingFile: String? = nil,
        absentFile: String? = nil, durationMs: Int = 0, superseded: Bool = false,
        timedOut: Bool = false
    ) {
        self.message = message
        self.log = log
        self.missingFile = missingFile
        self.absentFile = absentFile
        self.durationMs = durationMs
        self.superseded = superseded
        self.timedOut = timedOut
    }

    static let supersededByNewer = BuildError("superseded by a newer build", superseded: true)
    static let cancelled = BuildError("cancelled", superseded: true)

    static func timedOut(after seconds: Int) -> BuildError {
        BuildError("Stopped after \(seconds) s", durationMs: seconds * 1000, timedOut: true)
    }

    /// A build that failed because nothing has been downloaded yet: without the
    /// format file the engine cannot even start, so the log says nothing useful.
    public var isColdCache: Bool { message.contains("tectonic-format-") }
}

/// Jobs run one at a time per build directory. Every build for a document
/// writes the same `.scribex-build` directory, so two workers at once interleave
/// their `.aux`/`.log`/`.pdf` writes: multi-pass documents stop converging, and
/// we could read back the *other* run's PDF. Live preview makes overlap the
/// norm, since a compile outlasts the 600 ms debounce. Documents in different
/// folders build side by side, so one that never finishes holds up no other.
///
/// A preview is dropped once a newer one for the same document exists, and
/// stopped if it is already running, which keeps the editor from falling a
/// build behind after a burst of typing, and lets fixing a document that loops
/// forever take effect at once.
public actor Typesetter {
    /// Dropping is only safe when the job's output is all it was for. A job that
    /// fetches resources also fills the shared cache, which outlives the unwanted
    /// PDF, so priming the cache or an explicit "fetch it" always runs.
    public enum IfSuperseded: Sendable {
        case drop, run
    }

    /// Its absence makes the app offer the first-run download.
    static let readyMarker = "cache-ready"

    /// CPU seconds an offline build may take, unless the caller sets its own.
    public static let timeLimit = 30

    private let worker: URL
    /// CPU seconds before the worker is stopped. Real documents take a second
    /// or two; a download also spends CPU on decompression and on building the
    /// format file.
    private let cpuLimit: (offline: Int, online: Int)
    /// Wall-clock seconds, for a job that hangs without spending CPU. Downloads
    /// take as long as the connection makes them, so only offline builds have one.
    private let wallLimit: Int
    private var tickets: UInt64 = 0
    /// By build directory. Forgotten when idle, tickets and all, since no job
    /// is left to compare against them.
    private var lanes: [String: Lane] = [:]

    private struct Lane {
        /// Held for the whole job, PDF read included, so the bytes we return
        /// are the ones our own worker wrote.
        var running = false
        var waiting: [CheckedContinuation<Void, Never>] = []
        /// The newest ticket for each document that builds here.
        var latest: [String: UInt64] = [:]
        var current: (document: String, droppable: Bool, job: WorkerJob)?
    }

    public init(worker: URL) {
        self.init(worker: worker, cpuLimit: (offline: Self.timeLimit, online: 300), wallLimit: Self.timeLimit * 2)
    }

    init(worker: URL, cpuLimit: (offline: Int, online: Int), wallLimit: Int) {
        self.worker = worker
        self.cpuLimit = cpuLimit
        self.wallLimit = wallLimit
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
    /// background thread. `timeLimit`, in CPU seconds, replaces the default for
    /// an offline build, and allows twice that on the clock.
    public func typeset(
        entry: URL,
        source: String,
        onlyCached: Bool,
        ifSuperseded: IfSuperseded = .drop,
        timeLimit: Int? = nil,
        onFetch: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws(BuildError) -> Build {
        let outDir = Self.outputDirectory(for: entry).path
        // Two spellings of one folder (through a symlink, say) must still share
        // a lane: their workers would write the same build directory.
        let lane = entry.deletingLastPathComponent().resolvingSymlinksInPath().path
        let document = entry.path
        // Claimed even by jobs that will not drop themselves, so that they still
        // supersede the previews queued or running ahead of them.
        tickets += 1
        let ticket = tickets
        lanes[lane, default: Lane()].latest[document] = ticket
        if let current = lanes[lane]?.current, current.document == document, current.droppable {
            current.job.stop(.superseded)
        }
        await acquire(lane)
        defer { release(lane) }
        if Task.isCancelled {
            throw .cancelled
        }
        if ifSuperseded == .drop, lanes[lane]!.latest[document]! > ticket {
            throw .supersededByNewer
        }

        let job = WorkerJob()
        lanes[lane]!.current = (document, ifSuperseded == .drop, job)
        defer { lanes[lane]?.current = nil }
        let request = WorkerRequest(
            entry: entry.path,
            source: source,
            outDir: outDir,
            onlyCached: onlyCached,
            cpuLimit: onlyCached ? timeLimit ?? cpuLimit.offline : cpuLimit.online
        )
        let wall = onlyCached ? timeLimit.map { $0 * 2 } ?? wallLimit : nil
        let response = await withTaskCancellationHandler {
            await Self.run(worker, request, job: job, wallLimit: wall, onFetch: onFetch)
        } onCancel: {
            job.stop(.cancelled)
        }
        switch response {
        case .stopped(.superseded):
            throw .supersededByNewer
        case .stopped(.cancelled):
            throw .cancelled
        case let .stopped(.timedOut(seconds)):
            throw .timedOut(after: seconds)
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

    private func acquire(_ lane: String) async {
        if !lanes[lane]!.running {
            lanes[lane]!.running = true
            return
        }
        await withCheckedContinuation { lanes[lane]!.waiting.append($0) }
    }

    private func release(_ lane: String) {
        if lanes[lane]!.waiting.isEmpty {
            lanes[lane] = nil
        } else {
            lanes[lane]!.waiting.removeFirst().resume()
        }
    }
}

/// One worker run, which the actor can stop while a background thread waits
/// for it to finish.
final class WorkerJob: Sendable {
    enum Stop: Sendable {
        case superseded, cancelled
        case timedOut(seconds: Int)
    }

    private let state = Mutex<(process: Process?, stop: Stop?)>((nil, nil))

    /// The first reason given is the one reported. A job stopped before its
    /// worker starts is ended as soon as it does.
    func stop(_ reason: Stop) {
        state.withLock {
            if $0.stop == nil { $0.stop = reason }
            // Once it has exited, its pid may already belong to another process.
            if $0.process?.isRunning == true { $0.process?.terminate() }
        }
    }

    func started(_ process: Process) {
        state.withLock {
            $0.process = process
            if $0.stop != nil { process.terminate() }
        }
    }

    var stopped: Stop? { state.withLock { $0.stop } }
}

struct WorkerRequest: Encodable {
    var entry: String
    var source: String
    var outDir: String
    var onlyCached: Bool
    /// In seconds. Ending the worker from inside means a worker the app can no
    /// longer reach still stops.
    var cpuLimit: Int

    enum CodingKeys: String, CodingKey {
        case entry, source
        case outDir = "out_dir"
        case onlyCached = "only_cached"
        case cpuLimit = "cpu_limit_s"
    }
}

enum WorkerResponse: Decodable {
    case ok(log: String, durationMs: Int)
    case err(message: String, log: String, missingFile: String?, absentFile: String?, durationMs: Int)
    /// Ended before it answered; never decoded, the worker has no say in it.
    case stopped(WorkerJob.Stop)

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
        _ worker: URL, _ request: WorkerRequest, job: WorkerJob, wallLimit: Int?,
        onFetch: @escaping @Sendable (String) -> Void
    ) async -> WorkerResponse {
        await withCheckedContinuation { done in
            DispatchQueue.global(qos: .userInitiated).async {
                done.resume(returning: runBlocking(worker, request, job: job, wallLimit: wallLimit, onFetch: onFetch))
            }
        }
    }

    private static func runBlocking(
        _ worker: URL, _ request: WorkerRequest, job: WorkerJob, wallLimit: Int?,
        onFetch: @escaping @Sendable (String) -> Void
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
        job.started(process)
        let deadline = wallLimit.map { seconds in
            let stop = DispatchWorkItem { job.stop(.timedOut(seconds: seconds)) }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(seconds), execute: stop)
            return stop
        }
        defer { deadline?.cancel() }

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
            if let stop = job.stopped {
                return .stopped(stop)
            }
            if process.terminationReason == .uncaughtSignal, process.terminationStatus == SIGXCPU {
                return .stopped(.timedOut(seconds: request.cpuLimit))
            }
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
