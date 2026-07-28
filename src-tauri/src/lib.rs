mod engine;
mod worker;

use std::path::{Path, PathBuf};
use std::sync::Mutex;

/// Offline-first: the engine refuses network access unless the user opts in.
struct Settings {
    only_cached: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self { only_cached: true }
    }
}

#[derive(serde::Serialize)]
struct CompileOk {
    pdf: Vec<u8>,
    log: String,
    duration_ms: u64,
}

#[derive(serde::Serialize)]
struct CompileErr {
    message: String,
    log: String,
    missing_file: Option<String>,
    duration_ms: u64,
}

fn err(message: impl Into<String>) -> CompileErr {
    CompileErr { message: message.into(), log: String::new(), missing_file: None, duration_ms: 0 }
}

#[tauri::command]
fn set_offline(state: tauri::State<'_, Mutex<Settings>>, offline: bool) {
    state.lock().unwrap().only_cached = offline;
}

#[tauri::command]
fn get_offline(state: tauri::State<'_, Mutex<Settings>>) -> bool {
    state.lock().unwrap().only_cached
}

/// Path of the PDF a build for `entry` produces.
fn pdf_path_for(entry: &Path) -> PathBuf {
    engine::out_dir_for(entry).join(
        entry
            .file_stem()
            .map(|s| PathBuf::from(s).with_extension("pdf"))
            .unwrap_or_else(|| PathBuf::from("main.pdf")),
    )
}

/// Typeset `source` in a worker process and return the resulting PDF bytes.
async fn typeset(entry: PathBuf, source: String, only_cached: bool) -> Result<CompileOk, CompileErr> {
    let out_dir = engine::out_dir_for(&entry);
    let pdf_path = pdf_path_for(&entry);

    let req = worker::Request { entry, source, out_dir, only_cached };
    let resp = tauri::async_runtime::spawn_blocking(move || worker::run(req))
        .await
        .map_err(|e| err(format!("worker task failed: {e}")))?;

    match resp {
        worker::Response::Ok { log, duration_ms } => {
            let pdf = std::fs::read(&pdf_path).map_err(|e| CompileErr {
                message: format!("no PDF produced: {e}"),
                log: log.clone(),
                missing_file: None,
                duration_ms,
            })?;
            Ok(CompileOk { pdf, log, duration_ms })
        }
        worker::Response::Err { message, log, missing_file, duration_ms } => {
            Err(CompileErr { message, log, missing_file, duration_ms })
        }
    }
}

/// Typeset the editor buffer. Does not modify the document on disk.
#[tauri::command]
async fn compile_latex(
    state: tauri::State<'_, Mutex<Settings>>,
    path: String,
    source: String,
    // Overrides the global setting for a single "fetch missing resource" retry.
    allow_network: Option<bool>,
) -> Result<CompileOk, CompileErr> {
    let only_cached = match allow_network {
        Some(true) => false,
        _ => state.lock().unwrap().only_cached,
    };
    typeset(PathBuf::from(&path), source, only_cached).await
}

/// Write the buffer to disk. The only place the user's document is modified.
#[tauri::command]
fn save_document(path: String, source: String) -> Result<(), String> {
    let path = PathBuf::from(path);
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)
            .map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    }
    std::fs::write(&path, source).map_err(|e| format!("cannot save {}: {e}", path.display()))
}

/// Copy the most recent build output to a user-chosen destination.
#[tauri::command]
fn export_pdf(path: String, dest: String) -> Result<u64, String> {
    let src = pdf_path_for(&PathBuf::from(&path));
    if !src.exists() {
        return Err("nothing to export yet — build the document first".into());
    }
    std::fs::copy(&src, &dest).map_err(|e| format!("cannot write {dest}: {e}"))
}

/// Prime the offline cache with the common package and font set.
#[tauri::command]
async fn warmup_cache(dir: String) -> Result<u64, CompileErr> {
    let work = PathBuf::from(dir).join("warmup");
    std::fs::create_dir_all(&work).map_err(|e| err(format!("cannot stage warmup: {e}")))?;
    typeset(work.join("warmup.tex"), engine::WARMUP.to_string(), false)
        .await
        .map(|ok| ok.duration_ms)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Re-exec'd as the crash-isolated typesetting worker; never reaches the GUI.
    if std::env::args().any(|a| a == worker::FLAG) {
        worker::main();
    }

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .manage(Mutex::new(Settings::default()))
        .invoke_handler(tauri::generate_handler![
            compile_latex,
            save_document,
            export_pdf,
            warmup_cache,
            set_offline,
            get_offline
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
