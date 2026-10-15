//! Each build runs in its own worker process, talking JSON over stdio, so a
//! Tectonic abort kills only the worker and every run starts from clean engine
//! state (see `engine.rs`). The app's side of the protocol is `Typesetter.swift`.

use serde::{Deserialize, Serialize};
use std::fmt::Arguments;
use std::io::Write;
use std::path::PathBuf;
use tectonic::status::{MessageKind, StatusBackend};

/// Download progress goes to stderr: stdout carries only the JSON response,
/// which the parent can't read until the job ends.
const FETCH: &str = "scribex-fetch\t";

/// Only downloads are forwarded; everything else Tectonic reports is in the log.
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

#[derive(Deserialize)]
pub struct Request {
    /// Where the document lives (or would live). Used for the filesystem root
    /// and job name only — the file itself is never read or written.
    pub entry: PathBuf,
    pub source: String,
    pub out_dir: PathBuf,
    pub only_cached: bool,
    /// CPU seconds the build may use. TeX has no limit of its own, and a
    /// document can loop forever (a command redefined in terms of itself).
    #[serde(default)]
    pub cpu_limit_s: Option<u64>,
}

#[derive(Serialize)]
#[serde(tag = "status")]
pub enum Response {
    #[serde(rename = "ok")]
    Ok { log: String, duration_ms: u64 },
    #[serde(rename = "err")]
    Err {
        message: String,
        log: String,
        missing_file: Option<String>,
        /// A file the document needs that no download can supply.
        #[serde(default)]
        absent_file: Option<String>,
        duration_ms: u64,
    },
}

/// The PDF is left on disk for the parent to pick up, so it never has to
/// survive a round trip through JSON.
pub fn main() -> ! {
    exit_with_parent();
    let resp = match serde_json::from_reader::<_, Request>(std::io::stdin()) {
        Ok(req) => {
            if let Some(secs) = req.cpu_limit_s {
                limit_cpu(secs);
            }
            match crate::engine::compile(
                &req.entry,
                &req.source,
                &req.out_dir,
                req.only_cached,
                &mut Progress,
            ) {
                Ok(ok) => Response::Ok {
                    log: ok.log,
                    duration_ms: ok.duration_ms,
                },
                Err(e) => Response::Err {
                    message: e.message,
                    log: e.log,
                    missing_file: e.missing_file,
                    absent_file: e.absent_file,
                    duration_ms: e.duration_ms,
                },
            }
        }
        Err(e) => Response::Err {
            message: format!("bad request: {e}"),
            log: String::new(),
            missing_file: None,
            absent_file: None,
            duration_ms: 0,
        },
    };

    let _ = serde_json::to_writer(std::io::stdout(), &resp);
    std::process::exit(0)
}

/// Past the limit the kernel ends the worker with SIGXCPU, which the app
/// reports as a build that ran too long.
fn limit_cpu(secs: u64) {
    let limit = libc::rlimit {
        rlim_cur: secs,
        rlim_max: secs,
    };
    unsafe { libc::setrlimit(libc::RLIMIT_CPU, &limit) };
}

/// macOS has no way to have a child signalled when its parent dies, and a
/// running worker never touches its pipes, so it would not notice the app
/// quitting or crashing: it would be adopted by launchd and run on.
fn exit_with_parent() {
    let parent = unsafe { libc::getppid() };
    // Already adopted: the app went away before we got here.
    if parent == 1 {
        unsafe { libc::_exit(1) }
    }
    std::thread::spawn(move || loop {
        std::thread::sleep(std::time::Duration::from_millis(500));
        if unsafe { libc::getppid() } != parent {
            unsafe { libc::_exit(1) }
        }
    });
}
