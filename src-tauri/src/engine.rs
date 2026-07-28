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

use std::path::{Path, PathBuf};
use tectonic::config::PersistentConfig;
use tectonic::driver::{OutputFormat, ProcessingSessionBuilder};
use tectonic::status::NoopStatusBackend;

#[derive(serde::Serialize)]
pub struct CompileOk {
    pub pdf: Vec<u8>,
    pub log: String,
    pub duration_ms: u64,
}

#[derive(serde::Serialize)]
pub struct CompileErr {
    pub message: String,
    pub log: String,
    /// True when the build failed only because a package was absent from the
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

/// Typeset `source` as if it were the file at `entry`, without touching that
/// file. The editor buffer is fed to the engine directly, so live preview never
/// writes to the user's document — saving is always explicit.
///
/// `entry`'s directory is still the filesystem root, so `\input`,
/// `\includegraphics` and friends resolve against the real project on disk.
/// Intermediates and the PDF land in `out_dir`, which is kept between runs so
/// aux/toc files survive and multi-pass documents converge.
pub fn compile(
    entry: &Path,
    source: &str,
    out_dir: &Path,
    only_cached: bool,
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

    if let Err(e) = std::fs::create_dir_all(out_dir) {
        return Err(fail(format!("cannot create output dir: {e}"), String::new()));
    }

    let mut status = NoopStatusBackend::default();
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
        .output_dir(out_dir)
        .output_format(OutputFormat::Pdf)
        .keep_logs(true)
        .keep_intermediates(true)
        .print_stdout(false);

    let stem = Path::new(name).file_stem().and_then(|s| s.to_str()).unwrap_or("main");
    let read_log = || std::fs::read_to_string(out_dir.join(format!("{stem}.log"))).unwrap_or_default();

    let mut sess = sb
        .create(&mut status)
        .map_err(|e| fail(format!("session: {e}"), read_log()))?;

    sess.run(&mut status)
        .map_err(|e| fail(e.to_string(), read_log()))?;

    let pdf = std::fs::read(out_dir.join(format!("{stem}.pdf")))
        .map_err(|e| fail(format!("no PDF produced: {e}"), read_log()))?;

    Ok(CompileOk { pdf, log: read_log(), duration_ms: ms(started) })
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

/// Where compiled output for a given entry file lives.
pub fn out_dir_for(entry: &Path) -> PathBuf {
    entry
        .parent()
        .unwrap_or(Path::new("."))
        .join(".scribex-build")
}
