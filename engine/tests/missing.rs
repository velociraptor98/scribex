//! Needs a primed Tectonic cache: these build offline, and on a cold cache
//! they report that and pass.

use std::io::Write;
use std::process::{Command, Stdio};

fn build(source: &str) -> serde_json::Value {
    let dir = std::env::temp_dir().join(format!("scribex-missing-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let req = serde_json::json!({
        "entry": dir.join("doc.tex"),
        "source": source,
        "out_dir": dir.join(".scribex-build"),
        "only_cached": true,
    });
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
        .write_all(req.to_string().as_bytes())
        .unwrap();
    let out = child.wait_with_output().unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    serde_json::from_slice(&out.stdout).unwrap()
}

fn cold(resp: &serde_json::Value) -> bool {
    let cold = resp["message"]
        .as_str()
        .unwrap_or("")
        .contains("tectonic-format");
    if cold {
        eprintln!("skipped: the Tectonic cache is not primed");
    }
    cold
}

#[test]
fn a_class_the_bundle_lacks_is_absent_not_fetchable() {
    let resp = build("\\documentclass{scribex-no-such-class}\n\\begin{document}x\\end{document}\n");
    if cold(&resp) {
        return;
    }
    assert_eq!(resp["status"], "err");
    assert_eq!(resp["missing_file"], serde_json::Value::Null, "{resp}");
    assert_eq!(resp["absent_file"], "scribex-no-such-class.cls");
}

#[test]
fn an_image_beside_the_document_is_absent() {
    let resp = build(
        "\\documentclass{article}\\usepackage{graphicx}\n\\begin{document}\\includegraphics{scribex-figure.png}\\end{document}\n",
    );
    if cold(&resp) {
        return;
    }
    assert_eq!(resp["absent_file"], "scribex-figure.png", "{resp}");
}
