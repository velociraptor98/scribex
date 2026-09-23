//! Crash-isolated typesetting worker.
//!
//! The GUI never links a compile call directly (see the warning in `engine.rs`);
//! it re-executes its own binary with `--typeset` and talks JSON over stdio. Two
//! reasons: a Tectonic abort kills only the worker, and each run starts from
//! clean engine global state.
//!
//! Re-exec beats a separate sidecar binary here because there is nothing extra
//! to bundle, sign, or notarize — it is the same executable.

use serde::{Deserialize, Serialize};
use std::fmt::Arguments;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::Stdio;
use tectonic::status::{MessageKind, StatusBackend};

pub const FLAG: &str = "--typeset";

/// Prefix of the stderr line the worker writes as it starts downloading a
/// resource. stdout carries the one JSON response and nothing else, so progress
/// travels on stderr, where it can be read while the job is still running.
const FETCH: &str = "scribex-fetch\t";

/// Forwards Tectonic's "downloading <file>" notes to the parent. Everything
/// else it says is in the log already.
struct Progress;

impl StatusBackend for Progress {
    fn report(&mut self, kind: MessageKind, args: Arguments, _err: Option<&tectonic::Error>) {
        if kind != MessageKind::Note {
            return;
        }
        let note = args.to_string();
        if let Some(name) = note.strip_prefix("downloading ") {
            let mut err = std::io::stderr().lock();
            let _ = writeln!(err, "{FETCH}{name}");
            let _ = err.flush();
        }
    }

    fn dump_error_logs(&mut self, _output: &[u8]) {}
}

#[derive(Serialize, Deserialize)]
pub struct Request {
    /// Where the document lives (or would live). Used for the filesystem root
    /// and job name only — the file itself is never read or written.
    pub entry: PathBuf,
    /// The editor buffer to typeset, which may differ from what is on disk.
    pub source: String,
    pub out_dir: PathBuf,
    pub only_cached: bool,
}

#[derive(Serialize, Deserialize)]
#[serde(tag = "status")]
pub enum Response {
    #[serde(rename = "ok")]
    Ok { log: String, duration_ms: u64 },
    #[serde(rename = "err")]
    Err {
        message: String,
        log: String,
        missing_file: Option<String>,
        duration_ms: u64,
    },
}

/// Worker entry point: read one request, typeset, write one response.
/// The PDF is left on disk for the parent to pick up, so it never
/// has to survive a round trip through JSON.
pub fn main() -> ! {
    let resp = match serde_json::from_reader::<_, Request>(std::io::stdin()) {
        Ok(req) => match crate::engine::compile(
            &req.entry,
            &req.source,
            &req.out_dir,
            req.only_cached,
            &mut Progress,
        ) {
            Ok(ok) => Response::Ok { log: ok.log, duration_ms: ok.duration_ms },
            Err(e) => Response::Err {
                message: e.message,
                log: e.log,
                missing_file: e.missing_file,
                duration_ms: e.duration_ms,
            },
        },
        Err(e) => Response::Err {
            message: format!("bad request: {e}"),
            log: String::new(),
            missing_file: None,
            duration_ms: 0,
        },
    };

    let _ = serde_json::to_writer(std::io::stdout(), &resp);
    std::process::exit(0)
}

/// Run one typesetting job in a fresh child process. Blocking; call from a
/// blocking task. `on_fetch` is called with each resource name as the engine
/// starts downloading it.
pub fn run(req: Request, mut on_fetch: impl FnMut(String) + Send + 'static) -> Response {
    let exe = match std::env::current_exe() {
        Ok(p) => p,
        Err(e) => return fail(format!("cannot locate worker: {e}")),
    };

    let mut child = match std::process::Command::new(exe)
        .arg(FLAG)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => return fail(format!("cannot start worker: {e}")),
    };

    // Drained on its own thread so progress arrives while the job runs, and so
    // a chatty engine can never block on a full pipe.
    let progress = child.stderr.take().map(|stderr| {
        std::thread::spawn(move || {
            for line in BufReader::new(stderr).lines().map_while(Result::ok) {
                if let Some(name) = line.strip_prefix(FETCH) {
                    on_fetch(name.to_string());
                }
            }
        })
    });

    if let Some(mut stdin) = child.stdin.take() {
        if let Err(e) = serde_json::to_writer(&mut stdin, &req) {
            return fail(format!("cannot send job: {e}"));
        }
        // Dropping stdin signals end-of-request to the worker.
    }

    let out = match child.wait_with_output() {
        Ok(o) => o,
        Err(e) => return fail(format!("worker wait failed: {e}")),
    };
    if let Some(t) = progress {
        let _ = t.join();
    }

    if out.stdout.is_empty() {
        // No response at all: the engine aborted (see engine.rs) or was killed.
        // Isolating this is the entire point of the worker process.
        return fail(format!(
            "the typesetting engine crashed ({}). Your document is safe; \
             please report this with the source that triggered it.",
            out.status
        ));
    }

    serde_json::from_slice(&out.stdout)
        .unwrap_or_else(|e| fail(format!("malformed worker response: {e}")))
}

fn fail(message: String) -> Response {
    Response::Err { message, log: String::new(), missing_file: None, duration_ms: 0 }
}
