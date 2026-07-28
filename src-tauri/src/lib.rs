mod engine;
mod worker;

use std::path::PathBuf;
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

/// Typeset `entry` in a worker process and return the resulting PDF bytes.
async fn typeset(entry: PathBuf, only_cached: bool) -> Result<CompileOk, CompileErr> {
    let out_dir = engine::out_dir_for(&entry);
    let pdf_path = out_dir.join(
        entry
            .file_stem()
            .map(|s| PathBuf::from(s).with_extension("pdf"))
            .unwrap_or_else(|| PathBuf::from("main.pdf")),
    );

    let req = worker::Request { entry, out_dir, only_cached };
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

/// Write `source` to `path`, then typeset it.
#[tauri::command]
async fn compile_latex(
    state: tauri::State<'_, Mutex<Settings>>,
    path: String,
    source: String,
    // Overrides the global setting for a single "fetch missing resource" retry.
    allow_network: Option<bool>,
) -> Result<CompileOk, CompileErr> {
    let entry = PathBuf::from(&path);
    let only_cached = match allow_network {
        Some(true) => false,
        _ => state.lock().unwrap().only_cached,
    };

    std::fs::write(&entry, &source)
        .map_err(|e| err(format!("cannot write {}: {e}", entry.display())))?;

    typeset(entry, only_cached).await
}

/// Prime the offline cache with the common package and font set.
#[tauri::command]
async fn warmup_cache(dir: String) -> Result<u64, CompileErr> {
    let work = PathBuf::from(dir).join("warmup");
    std::fs::create_dir_all(&work).map_err(|e| err(format!("cannot stage warmup: {e}")))?;
    let entry = work.join("warmup.tex");
    std::fs::write(&entry, engine::WARMUP)
        .map_err(|e| err(format!("cannot stage warmup: {e}")))?;

    typeset(entry, false).await.map(|ok| ok.duration_ms)
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
            warmup_cache,
            set_offline,
            get_offline
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
