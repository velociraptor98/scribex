//! Needs a primed Tectonic cache: these build offline, and on a cold cache
//! the document fails fast instead of looping, which they report and pass.

use std::io::Write;
use std::os::unix::process::ExitStatusExt;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

/// Documents TeX never finishes, and never gives up on either: none of them
/// fills one of its fixed-size tables, as `\newcommand{\R}{\R^n}` does.
const RUNAWAYS: &[(&str, &str)] = &[
    (
        "a command redefined in terms of itself",
        "\\documentclass{article}\n\\renewcommand{\\vec}[1]{\\vec{\\mathbf{#1}}}\n\
         \\begin{document}\n$\\vec{x}$\n\\end{document}\n",
    ),
    (
        "a macro that is only itself",
        "\\documentclass{article}\n\\def\\a{\\a}\n\\begin{document}\n\\a\n\\end{document}\n",
    ),
    (
        "a \\loop whose counter never changes",
        "\\documentclass{article}\n\\begin{document}\n\\newcount\\n \\n=0\n\
         \\loop \\ifnum\\n<10 x \\repeat\n\\end{document}\n",
    ),
    (
        "an empty \\loop",
        "\\documentclass{article}\n\\begin{document}\n\\newcount\\n \\n=0\n\
         \\loop \\ifnum\\n<10 \\repeat\n\\end{document}\n",
    ),
];

const LOOPS: &str = RUNAWAYS[0].1;

fn request(name: &str, cpu_limit_s: Option<u64>) -> (std::path::PathBuf, String) {
    request_for(name, LOOPS, cpu_limit_s)
}

fn request_for(name: &str, source: &str, cpu_limit_s: Option<u64>) -> (std::path::PathBuf, String) {
    let dir = std::env::temp_dir().join(format!("scribex-limits-{name}-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let req = serde_json::json!({
        "entry": dir.join("doc.tex"),
        "source": source,
        "out_dir": dir.join(".scribex-build"),
        "only_cached": true,
        "cpu_limit_s": cpu_limit_s,
    });
    (dir, req.to_string())
}

fn alive(pid: i32) -> bool {
    unsafe { libc::kill(pid, 0) == 0 }
}

#[test]
fn every_document_that_loops_forever_is_stopped_by_its_cpu_limit() {
    let workers: Vec<_> = RUNAWAYS
        .iter()
        .enumerate()
        .map(|(i, &(what, source))| {
            std::thread::spawn(move || (what, stopped_by_cpu_limit(&format!("cpu{i}"), source)))
        })
        .collect();
    for worker in workers {
        let (what, stopped) = worker.join().unwrap();
        match stopped {
            Some(true) => {}
            Some(false) => panic!("{what}: the worker was not stopped by its limit"),
            None => return eprintln!("skipped: the Tectonic cache is not primed"),
        }
    }
}

/// None on a cold cache, where the document fails before it can loop.
fn stopped_by_cpu_limit(name: &str, source: &str) -> Option<bool> {
    let (dir, req) = request_for(name, source, Some(2));
    let started = Instant::now();
    let mut child = Command::new(env!("CARGO_BIN_EXE_scribex-typeset"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(req.as_bytes())
        .unwrap();
    let out = child.wait_with_output().unwrap();
    let _ = std::fs::remove_dir_all(&dir);

    if out.status.success() {
        let resp: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap();
        assert!(
            resp["message"].as_str().unwrap_or("").contains("tectonic-format"),
            "{name}: expected the build to be stopped: {resp}"
        );
        return None;
    }
    Some(
        out.status.signal() == Some(libc::SIGXCPU)
            && out.stdout.is_empty()
            && started.elapsed() < Duration::from_secs(30),
    )
}

#[test]
fn a_worker_whose_app_has_gone_exits() {
    let (dir, req) = request("orphan", None);
    let req_file = dir.join("request.json");
    std::fs::write(&req_file, req).unwrap();

    // The shell stands in for the app: it starts the worker, then exits while
    // the worker is busy, and the worker is adopted by launchd.
    let out = Command::new("/bin/sh")
        .arg("-c")
        .arg("\"$0\" < \"$1\" > /dev/null 2>&1 & echo $!; sleep 1")
        .arg(env!("CARGO_BIN_EXE_scribex-typeset"))
        .arg(&req_file)
        .output()
        .unwrap();
    let pid: i32 = String::from_utf8(out.stdout).unwrap().trim().parse().unwrap();

    let deadline = Instant::now() + Duration::from_secs(5);
    while alive(pid) && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(100));
    }
    let survived = alive(pid);
    if survived {
        unsafe { libc::kill(pid, libc::SIGKILL) };
    }
    let _ = std::fs::remove_dir_all(&dir);
    assert!(!survived, "the worker outlived its parent");
}
