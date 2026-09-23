//! A document must not be able to write outside its build directory.
//!
//! Runs the real worker (`scribex --typeset`) on a document that tries to
//! `\openout` through `../` and an absolute path. Needs a primed Tectonic cache,
//! since the build runs offline; on a cold cache it reports that and passes.

use std::io::Write;
use std::process::{Command, Stdio};

#[test]
fn openout_cannot_escape_the_build_dir() {
    let dir = std::env::temp_dir().join(format!("scribex-containment-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let proj = dir.join("proj");
    std::fs::create_dir_all(&proj).unwrap();
    let abs = dir.join("abs-escape.txt");

    let source = format!(
        "\\documentclass{{article}}\n\\newwrite\\f\n\
         \\immediate\\openout\\f=../rel-escape.txt\\immediate\\write\\f{{x}}\\immediate\\closeout\\f\n\
         \\immediate\\openout\\f={}\\immediate\\write\\f{{x}}\\immediate\\closeout\\f\n\
         \\begin{{document}}hi\\end{{document}}\n",
        abs.display()
    );
    let req = serde_json::json!({
        "entry": proj.join("doc.tex"),
        "source": source,
        "out_dir": proj.join(".scribex-build"),
        "only_cached": true,
    });

    let mut child = Command::new(env!("CARGO_BIN_EXE_scribex"))
        .arg("--typeset")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(req.to_string().as_bytes()).unwrap();
    let out = child.wait_with_output().unwrap();
    let resp: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap();

    if resp["status"] != "ok" && resp["message"].as_str().unwrap_or("").contains("tectonic-format") {
        eprintln!("skipped: the Tectonic cache is not primed");
        return;
    }
    assert_eq!(resp["status"], "ok", "build failed: {resp}");
    assert!(proj.join(".scribex-build/doc.pdf").exists(), "the PDF should still be written");
    assert!(!proj.join("rel-escape.txt").exists(), "relative \\openout escaped");
    assert!(!abs.exists(), "absolute \\openout escaped");
    let _ = std::fs::remove_dir_all(&dir);
}
