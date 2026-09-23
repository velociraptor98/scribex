//! Tectonic-backed typesetting. No TeX Live on disk; the engine is linked in.
//!
//! IMPORTANT: this module must only ever be called from the short-lived worker
//! process (`scribex --typeset`), never from the GUI process. Tectonic's C
//! engines keep global state, and a *failed* xdvipdfmx run leaves a stale output
//! handle behind. The next call then panics inside `ttbc_output_close`, which is
//! `extern "C"` and therefore cannot unwind — so it aborts the process outright.
//! Upstream's CLI never trips over this because it runs one process per
//! document; we do the same. See `worker.rs`.
//!
//! `only_cached` is the offline switch: when true the bundle refuses all network
//! access and any resource missing from the local cache fails the build.

use std::io::Write;
use std::path::{Component, Path, PathBuf};
use tectonic::config::PersistentConfig;
use tectonic::driver::{OutputFormat, ProcessingSessionBuilder};
use tectonic::io::memory::MemoryFileCollection;
use tectonic::status::StatusBackend;

pub struct CompileOk {
    pub log: String,
    pub duration_ms: u64,
}

pub struct CompileErr {
    pub message: String,
    pub log: String,
    /// Set when the build failed only because a resource was absent from the
    /// offline cache — the UI offers "fetch it" rather than showing a TeX error.
    pub missing_file: Option<String>,
    pub duration_ms: u64,
}

/// Identify a resource absent from the offline cache.
///
/// Two distinct shapes matter, and both are common on a cold cache:
///   `! LaTeX Error: File `tikz.sty' not found.`
///   `! Font TU/lmr/m/n/17.28=[lmroman17-regular]:... not loadable: Metric
///    (TFM) file or installed font not found.`
/// The font form carries no backtick-quoted name, so it needs its own rule.
fn missing_file_from_log(log: &str) -> Option<String> {
    // TeX hard-wraps the log at ~79 columns, so a single diagnostic is often
    // split mid-word. Join first, then match.
    let joined = log.replace("\n", "");

    if let Some(i) = joined.find("' not found") {
        if let Some(start) = joined[..i].rfind('`') {
            let name = &joined[start + 1..i];
            if !name.is_empty() && name.len() < 120 {
                return Some(name.to_string());
            }
        }
    }

    if joined.contains("installed font not found") || joined.contains("not loadable") {
        // Font name appears in brackets: =[lmroman17-regular]:mapping=...
        if let Some(open) = joined.find("=[") {
            if let Some(close) = joined[open + 2..].find(']') {
                let name = &joined[open + 2..open + 2 + close];
                if !name.is_empty() && name.len() < 120 {
                    return Some(name.to_string());
                }
            }
        }
        return Some("a required font".to_string());
    }

    None
}

/// A bare file name that stays inside the directory it is joined to: no
/// separators, no `..`, not absolute. TeX's `\openout` takes any name the
/// document gives it, and `Path::join` with an absolute path discards the base.
fn is_plain_name(name: &str) -> bool {
    let mut parts = Path::new(name).components();
    matches!((parts.next(), parts.next()), (Some(Component::Normal(_)), None))
}

/// Refuse a build directory that is not a real directory. A project arrives
/// with whatever `.scribex-build` its author left in it, and a symlink there
/// would send every output file wherever it points.
fn ensure_real_dir(dir: &Path) -> Result<(), String> {
    match std::fs::symlink_metadata(dir) {
        Ok(m) if m.file_type().is_dir() => Ok(()),
        Ok(_) => Err(format!("{} is not a directory; refusing to build into it", dir.display())),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            std::fs::create_dir_all(dir).map_err(|e| format!("cannot create output dir: {e}"))
        }
        Err(e) => Err(format!("cannot inspect output dir: {e}")),
    }
}

/// Write the engine's in-memory outputs into `out_dir`.
///
/// Tectonic would otherwise write them itself, to `out_dir.join(name)` for
/// every name the document chose, so a hostile document could create or
/// overwrite any file the user can (`~/.zshrc`, a LaunchAgent). Only plain names
/// are written here, and an existing entry is replaced rather than written
/// through, so a planted symlink cannot redirect the write either.
fn write_outputs(files: &MemoryFileCollection, out_dir: &Path) -> Result<(), String> {
    for (name, file) in files {
        if !is_plain_name(name) || file.data.is_empty() {
            continue;
        }
        let dest = out_dir.join(name);
        match std::fs::remove_file(&dest) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(format!("cannot replace {name}: {e}")),
        }
        // `create_new` is O_EXCL, which also refuses to follow a symlink that
        // appeared since the removal.
        std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&dest)
            .and_then(|mut f| f.write_all(&file.data))
            .map_err(|e| format!("cannot write {name}: {e}"))?;
    }
    Ok(())
}

/// Typeset `source` as if it were the file at `entry`, without touching that
/// file. The editor buffer is fed to the engine directly, so live preview never
/// writes to the user's document — only `save_document` does.
///
/// `status` hears Tectonic's progress notes, including each resource it
/// downloads; the worker forwards those to the GUI.
///
/// `entry`'s directory is still the filesystem root, so `\input`,
/// `\includegraphics` and friends resolve against the real project on disk.
/// Intermediates and the PDF land in `out_dir` (see `write_outputs`), which is
/// kept between runs so aux/toc files survive and multi-pass documents converge.
pub fn compile(
    entry: &Path,
    source: &str,
    out_dir: &Path,
    only_cached: bool,
    status: &mut dyn StatusBackend,
) -> Result<CompileOk, CompileErr> {
    let started = std::time::Instant::now();
    let ms = |t: std::time::Instant| t.elapsed().as_millis() as u64;

    let fail = |msg: String, log: String| CompileErr {
        missing_file: missing_file_from_log(&log),
        message: msg,
        log,
        duration_ms: ms(started),
    };

    let root = entry.parent().unwrap_or(Path::new("."));
    let name = entry
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("main.tex");

    ensure_real_dir(out_dir).map_err(|e| fail(e, String::new()))?;

    let config = PersistentConfig::open(false)
        .map_err(|e| fail(format!("tectonic config: {e}"), String::new()))?;
    let bundle = config
        .default_bundle(only_cached)
        .map_err(|e| fail(format!("tectonic bundle: {e}"), String::new()))?;
    let fmt_cache = config
        .format_cache_path()
        .map_err(|e| fail(format!("format cache: {e}"), String::new()))?;

    let mut sb = ProcessingSessionBuilder::default();
    sb.bundle(bundle)
        .primary_input_buffer(source.as_bytes())
        .tex_input_name(name)
        .format_name("latex")
        .format_cache_path(fmt_cache)
        .filesystem_root(root)
        // Outputs stay in memory; `write_outputs` puts the safe ones on disk.
        .do_not_write_output_files()
        .output_format(OutputFormat::Pdf)
        .print_stdout(false);

    let stem = Path::new(name).file_stem().and_then(|s| s.to_str()).unwrap_or("main");
    let log_of = |files: &MemoryFileCollection| {
        files
            .get(&format!("{stem}.log"))
            .map(|f| String::from_utf8_lossy(&f.data).into_owned())
            .unwrap_or_default()
    };

    let mut sess = sb
        .create(status)
        .map_err(|e| fail(format!("session: {e}"), String::new()))?;

    let run = sess.run(status);
    let files = sess.into_file_data();
    let log = log_of(&files);
    if let Err(e) = run {
        return Err(fail(e.to_string(), log));
    }

    if !files.contains_key(&format!("{stem}.pdf")) {
        return Err(fail("no PDF produced".into(), log));
    }
    write_outputs(&files, out_dir).map_err(|e| fail(e, log.clone()))?;

    Ok(CompileOk { log, duration_ms: ms(started) })
}

/// A document that touches the resources a cold cache is most likely to lack:
/// title fonts at display sizes, math fonts, and the common package set. Run
/// once with network access so that ordinary editing works offline afterwards.
pub const WARMUP: &str = r#"\documentclass{article}
\usepackage{amsmath,amssymb,graphicx,hyperref,geometry,xcolor,booktabs}
\title{Warmup}\author{ScribeX}\date{}
\begin{document}
\maketitle
\tableofcontents
\section{Text}\textbf{b} \textit{i} \texttt{t} \emph{e}
\subsection{Math}
\begin{equation}\int_{-\infty}^{\infty} e^{-x^2}\,dx=\sqrt{\pi}\end{equation}
\begin{align}a &= b \\ c &= d\end{align}
$\mathbb{R}\ \mathcal{L}\ \mathfrak{g}\ \alpha\beta\gamma$
\begin{itemize}\item one\end{itemize}
\begin{enumerate}\item one\end{enumerate}
\begin{tabular}{ll}\toprule a & b \\ \bottomrule\end{tabular}
\end{document}
"#;

pub fn out_dir_for(entry: &Path) -> PathBuf {
    entry
        .parent()
        .unwrap_or(Path::new("."))
        .join(".scribex-build")
}

#[cfg(test)]
mod tests {
    use super::*;
    use tectonic::io::memory::MemoryFileInfo;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("scribex-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn outputs(entries: &[(&str, &str)]) -> MemoryFileCollection {
        entries
            .iter()
            .map(|(n, d)| (n.to_string(), MemoryFileInfo { data: d.as_bytes().to_vec(), unix_mtime: None }))
            .collect()
    }

    #[test]
    fn plain_names_only() {
        assert!(is_plain_name("doc.pdf"));
        assert!(is_plain_name(".hidden"));
        for bad in ["", ".", "..", "../x", "a/b", "/tmp/x", "./x"] {
            assert!(!is_plain_name(bad), "{bad:?} should be rejected");
        }
    }

    #[test]
    fn escaping_names_are_not_written() {
        let dir = scratch("escape");
        let out = dir.join("out");
        std::fs::create_dir(&out).unwrap();
        let abs = dir.join("abs.txt");
        let files = outputs(&[
            ("doc.pdf", "pdf"),
            ("../rel.txt", "x"),
            (abs.to_str().unwrap(), "x"),
            ("", "stdout"),
        ]);

        write_outputs(&files, &out).unwrap();

        assert_eq!(std::fs::read_to_string(out.join("doc.pdf")).unwrap(), "pdf");
        assert!(!dir.join("rel.txt").exists());
        assert!(!abs.exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn planted_symlink_is_replaced_not_followed() {
        let dir = scratch("symlink");
        let out = dir.join("out");
        std::fs::create_dir(&out).unwrap();
        let target = dir.join("victim");
        std::fs::write(&target, "original").unwrap();
        std::os::unix::fs::symlink(&target, out.join("doc.aux")).unwrap();

        write_outputs(&outputs(&[("doc.aux", "aux")]), &out).unwrap();

        assert_eq!(std::fs::read_to_string(&target).unwrap(), "original");
        assert!(!std::fs::symlink_metadata(out.join("doc.aux")).unwrap().file_type().is_symlink());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn symlinked_build_dir_is_refused() {
        let dir = scratch("linkdir");
        std::fs::create_dir(dir.join("elsewhere")).unwrap();
        std::os::unix::fs::symlink(dir.join("elsewhere"), dir.join(".scribex-build")).unwrap();

        assert!(ensure_real_dir(&dir.join(".scribex-build")).is_err());
        assert!(ensure_real_dir(&dir.join("fresh")).is_ok());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
