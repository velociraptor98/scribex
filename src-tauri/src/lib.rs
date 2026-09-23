mod engine;
mod worker;

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use tauri::menu::{AboutMetadata, Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri::{Emitter, Manager};

/// Offline-first: the engine refuses network access unless the user opts in.
struct Settings {
    only_cached: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self { only_cached: true }
    }
}

/// Serializes typesetting jobs.
///
/// Every build for a document writes the same `.scribex-build` directory (see
/// `engine::out_dir_for`), so two workers running at once interleave their
/// `.aux`/`.log`/`.pdf` writes: multi-pass documents stop converging, and the
/// parent can read back a PDF produced by the *other* run. Live preview makes
/// overlap the normal case rather than the exception — the debounce is 600 ms
/// and a compile takes longer than that — so jobs are queued, not raced.
///
/// Queued jobs are also dropped once a newer one exists. Their output would be
/// discarded by the UI anyway, and skipping them keeps the editor from falling
/// a build behind after a burst of typing.
#[derive(Default)]
struct Builds {
    /// Held for the whole job, PDF read included, so the bytes we return are
    /// the ones our own worker wrote.
    slot: tauri::async_runtime::Mutex<()>,
    /// Highest ticket issued so far.
    latest: AtomicU64,
}

impl Builds {
    /// Take a ticket, superseding every job holding an older one.
    fn claim(&self) -> u64 {
        self.latest.fetch_add(1, Ordering::SeqCst) + 1
    }

    fn superseded(&self, ticket: u64) -> bool {
        self.latest.load(Ordering::SeqCst) > ticket
    }
}

/// What to do with a queued job that a newer one has overtaken.
///
/// Dropping is only safe when the job's *output* is all it was for, which is
/// true of a preview: the UI shows the newest build and throws the rest away.
/// A job that fetches resources also populates the shared cache on disk, and
/// that outlives the PDF nobody looks at — so priming the cache, or an explicit
/// "fetch it", runs to completion even once its result is unwanted. Dropping
/// those would silently skip the one thing the user actually asked for.
#[derive(Clone, Copy, PartialEq)]
enum IfSuperseded {
    Drop,
    Run,
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
    /// True when a newer build replaced this one before it ran. Not a failure:
    /// the UI drops these instead of reporting them.
    superseded: bool,
}

fn err(message: impl Into<String>) -> CompileErr {
    CompileErr {
        message: message.into(),
        log: String::new(),
        missing_file: None,
        duration_ms: 0,
        superseded: false,
    }
}

fn superseded() -> CompileErr {
    CompileErr { superseded: true, ..err("superseded by a newer build") }
}

#[tauri::command]
fn set_offline(state: tauri::State<'_, Mutex<Settings>>, offline: bool) {
    state.lock().unwrap().only_cached = offline;
}

fn pdf_path_for(entry: &Path) -> PathBuf {
    engine::out_dir_for(entry).join(
        entry
            .file_stem()
            .map(|s| PathBuf::from(s).with_extension("pdf"))
            .unwrap_or_else(|| PathBuf::from("main.pdf")),
    )
}

/// Typeset `source` in a worker process and return the resulting PDF bytes.
///
/// One job runs at a time; see `Builds`. Each resource the engine downloads is
/// announced to the frontend as a `fetching` event carrying its file name.
async fn typeset(
    app: &tauri::AppHandle,
    builds: &Builds,
    entry: PathBuf,
    source: String,
    only_cached: bool,
    if_superseded: IfSuperseded,
) -> Result<CompileOk, CompileErr> {
    // Claimed even by jobs that will not drop themselves, so that they still
    // supersede the previews queued ahead of them.
    let ticket = builds.claim();
    let _slot = builds.slot.lock().await;
    if if_superseded == IfSuperseded::Drop && builds.superseded(ticket) {
        return Err(superseded());
    }

    let out_dir = engine::out_dir_for(&entry);
    let pdf_path = pdf_path_for(&entry);

    let req = worker::Request { entry, source, out_dir, only_cached };
    let app = app.clone();
    let on_fetch = move |name: String| {
        let _ = app.emit("fetching", name);
    };
    let resp = tauri::async_runtime::spawn_blocking(move || worker::run(req, on_fetch))
        .await
        .map_err(|e| err(format!("worker task failed: {e}")))?;

    match resp {
        worker::Response::Ok { log, duration_ms } => {
            let pdf = std::fs::read(&pdf_path).map_err(|e| CompileErr {
                message: format!("no PDF produced: {e}"),
                log: log.clone(),
                missing_file: None,
                duration_ms,
                superseded: false,
            })?;
            Ok(CompileOk { pdf, log, duration_ms })
        }
        worker::Response::Err { message, log, missing_file, duration_ms } => {
            Err(CompileErr { message, log, missing_file, duration_ms, superseded: false })
        }
    }
}

/// Typeset the editor buffer. Does not modify the document on disk.
#[tauri::command]
async fn compile_latex(
    app: tauri::AppHandle,
    settings: tauri::State<'_, Mutex<Settings>>,
    builds: tauri::State<'_, Builds>,
    path: String,
    source: String,
    // Overrides the global setting for a single "fetch missing resource" retry.
    allow_network: Option<bool>,
) -> Result<CompileOk, CompileErr> {
    let only_cached = match allow_network {
        Some(true) => false,
        _ => settings.lock().unwrap().only_cached,
    };
    // Only the explicit per-build override counts as a fetch the user asked
    // for. Leaving the global offline toggle off does not, or every keystroke
    // would queue an undroppable build.
    let if_superseded = match allow_network {
        Some(true) => IfSuperseded::Run,
        _ => IfSuperseded::Drop,
    };
    typeset(&app, &builds, PathBuf::from(&path), source, only_cached, if_superseded).await
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

/// Written once the first-run download has completed. Its absence is what
/// makes the frontend offer that download.
const READY_MARKER: &str = "cache-ready";

fn app_data(app: &tauri::AppHandle) -> Result<PathBuf, CompileErr> {
    app.path()
        .app_local_data_dir()
        .map_err(|e| err(format!("cannot locate app data: {e}")))
}

/// Whether the first-run download has completed on this machine. A marker
/// rather than a probe build, which takes seconds to fail on an empty cache. If
/// the cache is cleared later, `isColdCache` in App.tsx catches the failure.
#[tauri::command]
fn cache_ready(app: tauri::AppHandle) -> Result<bool, CompileErr> {
    Ok(app_data(&app)?.join(READY_MARKER).exists())
}

/// Prime the offline cache with the warmup set, then each of `documents` (the
/// built-in plates). An interrupted run can be retried; what arrived stays cached.
#[tauri::command]
async fn warmup_cache(
    app: tauri::AppHandle,
    builds: tauri::State<'_, Builds>,
    documents: Option<Vec<String>>,
) -> Result<u64, CompileErr> {
    let started = std::time::Instant::now();
    let dir = app_data(&app)?;
    let work = dir.join("warmup");
    std::fs::create_dir_all(&work).map_err(|e| err(format!("cannot stage warmup: {e}")))?;

    let jobs = std::iter::once(engine::WARMUP.to_string()).chain(documents.unwrap_or_default());
    for (i, source) in jobs.enumerate() {
        // Never dropped as superseded: the cache write is the point.
        typeset(
            &app,
            &builds,
            work.join(format!("warmup-{i}.tex")),
            source,
            false,
            IfSuperseded::Run,
        )
        .await?;
    }

    std::fs::write(dir.join(READY_MARKER), "")
        .map_err(|e| err(format!("cannot record setup: {e}")))?;
    Ok(started.elapsed().as_millis() as u64)
}

const QUIT_ID: &str = "scribex-quit";
const EXPORT_ID: &str = "scribex-export";

/// Tauri's default menu, with the predefined Quit item replaced by an ordinary
/// one.
///
/// Predefined Quit is wired to `NSApp terminate:` on macOS, which tears the
/// process down without ever emitting a close-requested event — so ⌘Q would
/// discard unsaved work without asking, no matter what the frontend does. Ours
/// closes the windows instead, which routes ⌘Q through the same guard as the
/// close button. Closing the last window still exits the app.
fn build_menu(app: &tauri::AppHandle) -> tauri::Result<Menu<tauri::Wry>> {
    let info = app.package_info();
    let name = info.name.clone();
    let quit = MenuItem::with_id(
        app,
        QUIT_ID,
        format!("Quit {name}"),
        true,
        Some("CmdOrCtrl+Q"),
    )?;
    let export = MenuItem::with_id(app, EXPORT_ID, "Export as PDF…", true, Some("CmdOrCtrl+E"))?;

    Menu::with_items(
        app,
        &[
            #[cfg(target_os = "macos")]
            &Submenu::with_items(
                app,
                &name,
                true,
                &[
                    &PredefinedMenuItem::about(
                        app,
                        None,
                        Some(AboutMetadata {
                            name: Some(name.clone()),
                            version: Some(info.version.to_string()),
                            ..Default::default()
                        }),
                    )?,
                    &PredefinedMenuItem::separator(app)?,
                    &PredefinedMenuItem::services(app, None)?,
                    &PredefinedMenuItem::separator(app)?,
                    &PredefinedMenuItem::hide(app, None)?,
                    &PredefinedMenuItem::hide_others(app, None)?,
                    &PredefinedMenuItem::separator(app)?,
                    &quit,
                ],
            )?,
            &Submenu::with_items(
                app,
                "File",
                true,
                &[
                    &export,
                    &PredefinedMenuItem::separator(app)?,
                    &PredefinedMenuItem::close_window(app, None)?,
                    #[cfg(not(target_os = "macos"))]
                    &quit,
                ],
            )?,
            // Without these the webview loses ⌘X/⌘C/⌘V on macOS.
            &Submenu::with_items(
                app,
                "Edit",
                true,
                &[
                    &PredefinedMenuItem::undo(app, None)?,
                    &PredefinedMenuItem::redo(app, None)?,
                    &PredefinedMenuItem::separator(app)?,
                    &PredefinedMenuItem::cut(app, None)?,
                    &PredefinedMenuItem::copy(app, None)?,
                    &PredefinedMenuItem::paste(app, None)?,
                    &PredefinedMenuItem::select_all(app, None)?,
                ],
            )?,
            #[cfg(target_os = "macos")]
            &Submenu::with_items(
                app,
                "View",
                true,
                &[&PredefinedMenuItem::fullscreen(app, None)?],
            )?,
            &Submenu::with_items(
                app,
                "Window",
                true,
                &[
                    &PredefinedMenuItem::minimize(app, None)?,
                    &PredefinedMenuItem::maximize(app, None)?,
                    #[cfg(target_os = "macos")]
                    &PredefinedMenuItem::separator(app)?,
                    &PredefinedMenuItem::close_window(app, None)?,
                ],
            )?,
        ],
    )
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Re-exec'd as the crash-isolated typesetting worker; never reaches the GUI.
    if std::env::args().any(|a| a == worker::FLAG) {
        worker::main();
    }

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .manage(Mutex::new(Settings::default()))
        .manage(Builds::default())
        .setup(|app| {
            app.set_menu(build_menu(app.handle())?)?;
            Ok(())
        })
        .on_menu_event(|app, event| {
            if event.id() == QUIT_ID {
                // Ask each window to close rather than exiting outright, so the
                // unsaved-changes guard in the frontend gets a say.
                for (_, window) in app.webview_windows() {
                    let _ = window.close();
                }
            } else if event.id() == EXPORT_ID {
                // The frontend owns the export dialog and knows whether there
                // is a PDF to export.
                let _ = app.emit("menu", "export");
            }
        })
        .invoke_handler(tauri::generate_handler![
            compile_latex,
            save_document,
            export_pdf,
            warmup_cache,
            cache_ready,
            set_offline
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
