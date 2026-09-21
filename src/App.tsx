import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { confirm, open, save } from "@tauri-apps/plugin-dialog";
import { readTextFile } from "@tauri-apps/plugin-fs";
import { appLocalDataDir } from "@tauri-apps/api/path";
import { getCurrentWindow } from "@tauri-apps/api/window";

import Editor, { EditorHandle } from "./Editor";
import PdfView from "./PdfView";
import TitleBar from "./TitleBar";
import Welcome from "./Welcome";
import Palette, { AppCommand } from "./Palette";
import ExportSheet from "./ExportSheet";
import { Marks, PressLog } from "./Marks";

import { bibKeys, outline, stats } from "./latex";
import { Diagnostic, Fix, PressRow, markKey, parseLog, pressLog } from "./texlog";
import { ARTICLE, Plate } from "./templates";
import { RecentDoc, documentTitle, loadRecent, remember } from "./recent";
import { ExportOptions, applyOptions, needsRebuild, sheetOf } from "./exporting";
import { CARET, selectionToTable } from "./commands";
import "./App.css";

interface CompileOk { pdf: number[]; log: string; duration_ms: number }
interface CompileErr {
  message: string;
  log: string;
  missing_file: string | null;
  duration_ms: number;
  /** A newer build replaced this one before it ran. Not a failure to report. */
  superseded?: boolean;
}

const DEBOUNCE_MS = 600;

type Screen = "welcome" | "editor";
type RightPane = "proof" | "marks";

export default function App() {
  const [screen, setScreen] = useState<Screen>("welcome");
  const [source, setSource] = useState(ARTICLE);
  const [path, setPath] = useState<string | null>(null);
  const [pdf, setPdf] = useState<Uint8Array | null>(null);
  const [diags, setDiags] = useState<Diagnostic[]>([]);
  const [press, setPress] = useState<PressRow[]>([]);
  const [status, setStatus] = useState("Ready");
  const [busy, setBusy] = useState(false);
  const [offline, setOffline] = useState(true);
  const [missing, setMissing] = useState<string | null>(null);
  const [zoom, setZoom] = useState(1.3);
  const [autoBuild, setAutoBuild] = useState(true);
  const [docKey, setDocKey] = useState(0);
  const [dirty, setDirty] = useState(false);
  const [buildMs, setBuildMs] = useState<number | undefined>();

  const [recent, setRecent] = useState<RecentDoc[]>(loadRecent);
  const [rightPane, setRightPane] = useState<RightPane>("proof");
  const [pages, setPages] = useState(0);
  const [page, setPage] = useState(1);
  const [pressOpen, setPressOpen] = useState(false);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [exportOpen, setExportOpen] = useState(false);
  const [selection, setSelection] = useState("");
  /** Marks the reader has waved through; cleared on every new build. */
  const [ignored, setIgnored] = useState<string[]>([]);
  const [keys, setKeys] = useState<{ keys: string[]; name?: string }>({ keys: [] });

  const editor = useRef<EditorHandle>(null);
  // Scratch file used until the user opens or saves a real document.
  const scratchPath = useRef<string | null>(null);
  const seq = useRef(0);
  // The source that produced the PDF on screen, so the export sheet knows
  // whether the paper size it shows is the one that was actually set.
  const built = useRef<string>("");

  const sections = useMemo(() => outline(source), [source]);
  // Indent relative to the shallowest heading present, so an article whose
  // top level is \section is not pushed in by the two levels (part, chapter)
  // it never uses — the margin is only 186px wide.
  const baseLevel = useMemo(
    () => (sections.length ? Math.min(...sections.map((s) => s.level)) : 0),
    [sections]
  );
  const tally = useMemo(() => stats(source), [source]);
  const name = path?.split("/").pop() ?? "untitled.tex";
  const visible = useMemo(
    () => diags.filter((d) => !ignored.includes(markKey(d))),
    [diags, ignored]
  );

  /* ── building ─────────────────────────────────────────────────────────── */

  const build = useCallback(
    async (src: string, allowNetwork = false) => {
      const target = path ?? scratchPath.current;
      if (!target) return;

      const mine = ++seq.current;
      setBusy(true);
      setStatus(allowNetwork ? "Fetching packages…" : "Typesetting…");
      try {
        const r = await invoke<CompileOk>("compile_latex", {
          path: target,
          source: src,
          allowNetwork: allowNetwork || undefined,
        });
        if (mine !== seq.current) return; // a newer build superseded this one
        const parsed = parseLog(r.log, { source: src, bibKeys: keys.keys, bibName: keys.name });
        setPdf(new Uint8Array(r.pdf));
        setDiags(parsed);
        setPress(pressLog(r.log, { source: src, name, diags: parsed }));
        setIgnored([]);
        setMissing(null);
        setBuildMs(r.duration_ms);
        built.current = src;
        setStatus(`Set in ${r.duration_ms} ms`);
      } catch (e) {
        const err = e as CompileErr;
        // The backend runs one job at a time and drops those a newer request
        // has overtaken. Leave the status alone — the newer build owns it now.
        if (err.superseded || mine !== seq.current) return;
        const parsed = parseLog(err.log ?? "", {
          source: src, bibKeys: keys.keys, bibName: keys.name,
        });
        setDiags(parsed);
        setPress(pressLog(err.log ?? "", { source: src, name, diags: parsed }));
        setIgnored([]);
        setMissing(err.missing_file ?? null);
        setBuildMs(err.duration_ms);
        setStatus(err.missing_file ? `Missing: ${err.missing_file}` : "Did not set");
        // A failed build leaves a stale proof on screen; the marks are the news.
        if (parsed.length > 0) setRightPane("marks");
      } finally {
        if (mine === seq.current) setBusy(false);
      }
    },
    [path, keys, name]
  );

  // Resolve a scratch path once, before anything can ask for a build. The
  // backend creates the directory when it first builds there.
  useEffect(() => {
    (async () => {
      const dir = await appLocalDataDir();
      scratchPath.current = `${dir}/scratch.tex`;
      await invoke("set_offline", { offline: true });
    })();
  }, []);

  // Debounced live rebuild, once a document is on screen.
  useEffect(() => {
    if (screen !== "editor" || !autoBuild) return;
    const t = setTimeout(() => build(source), DEBOUNCE_MS);
    return () => clearTimeout(t);
  }, [source, autoBuild, build, screen]);

  /** Bibliography keys, so an undefined citation can propose the right one. */
  const loadBib = useCallback(async (src: string, docPath: string | null) => {
    const dir = docPath?.split("/").slice(0, -1).join("/");
    if (!dir) return setKeys({ keys: [] });
    const named = [
      ...src.matchAll(/\\(?:bibliography|addbibresource)\s*\{([^}]+)\}/g),
    ].flatMap((m) => m[1].split(",").map((s) => s.trim()));
    const files = named.map((f) => (f.endsWith(".bib") ? f : `${f}.bib`));

    const all: string[] = [];
    let first: string | undefined;
    for (const f of files) {
      try {
        const text = await readTextFile(`${dir}/${f}`);
        const ks = bibKeys(text);
        if (ks.length && !first) first = f;
        all.push(...ks);
      } catch {
        // A missing .bib is itself a build error; nothing to add here.
      }
    }
    setKeys({ keys: all, name: first });
  }, []);

  /* ── documents ────────────────────────────────────────────────────────── */

  const adopt = useCallback(
    (text: string, docPath: string | null, note: string) => {
      setSource(text);
      setPath(docPath);
      setDocKey((k) => k + 1);
      setDiags([]);
      setPress([]);
      setIgnored([]);
      setMissing(null);
      setDirty(false);
      setPdf(null);
      setPages(0);
      setPage(1);
      setRightPane("proof");
      setScreen("editor");
      setStatus(note);
      loadBib(text, docPath);
      if (docPath) {
        setRecent(remember({
          path: docPath,
          title: documentTitle(text, docPath),
          sections: outline(text).length,
          citations: stats(text).citations,
        }));
      }
    },
    [loadBib]
  );

  async function openFile() {
    const picked = await open({ filters: [{ name: "LaTeX", extensions: ["tex"] }] });
    if (typeof picked !== "string") return;
    try {
      const text = await readTextFile(picked);
      adopt(text, picked, `Opened ${picked.split("/").pop()}`);
    } catch (e) {
      setStatus(`Cannot open: ${e}`);
    }
  }

  async function openRecent(doc: RecentDoc) {
    try {
      const text = await readTextFile(doc.path);
      adopt(text, doc.path, `Opened ${doc.path.split("/").pop()}`);
    } catch {
      setStatus(`${doc.path.split("/").pop()} has moved or been deleted`);
    }
  }

  /** Write the buffer to disk, prompting for a location if there isn't one yet. */
  async function saveFile(forceDialog = false) {
    let target = path;
    if (!target || forceDialog) {
      const picked = await save({
        defaultPath: target ?? "untitled.tex",
        filters: [{ name: "LaTeX", extensions: ["tex"] }],
      });
      if (typeof picked !== "string") return;
      target = picked;
    }
    try {
      await invoke("save_document", { path: target, source });
      // Adopting the new path also moves where future builds are rooted.
      if (target !== path) {
        setPath(target);
        loadBib(source, target);
      }
      setDirty(false);
      setStatus(`Saved ${target.split("/").pop()}`);
      setRecent(remember({
        path: target,
        title: documentTitle(source, target),
        sections: sections.length,
        citations: tally.citations,
      }));
    } catch (e) {
      setStatus(`Save failed: ${e}`);
    }
  }

  /** Export honouring the imprint sheet. Options that change the document are
   *  applied to a throwaway build; the buffer and the file are left alone. */
  async function runExport(opts: ExportOptions) {
    const target = path ?? scratchPath.current;
    if (!target) return;
    const stem = name.replace(/\.tex$/i, "");
    const dest = await save({
      defaultPath: `${stem}.pdf`,
      filters: [{ name: "PDF", extensions: ["pdf"] }],
    });
    if (typeof dest !== "string") return;

    const rebuild = needsRebuild(opts, sheetOf(source));
    setExportOpen(false);
    setBusy(true);
    try {
      if (rebuild) {
        setStatus("Setting for export…");
        // Bypass `build` so the on-screen proof is not replaced by the variant.
        seq.current++;
        await invoke<CompileOk>("compile_latex", {
          path: target,
          source: applyOptions(source, opts),
        });
      }

      const bytes = await invoke<number>("export_pdf", { path: target, dest });

      if (opts.sourceAlongside) {
        const beside = dest.replace(/\.pdf$/i, ".tex");
        await invoke("save_document", { path: beside, source });
      }

      setStatus(
        `Exported ${(bytes / 1024).toFixed(0)} KB to ${dest.split("/").pop()}` +
        (opts.sourceAlongside ? " (with source)" : "")
      );
    } catch (e) {
      setStatus(`Export failed: ${(e as CompileErr).message ?? e}`);
    } finally {
      setBusy(false);
      // Restore the proof, which the export build may have overwritten on disk.
      if (rebuild) build(source);
    }
  }

  // One-time download of the common package/font set so that everyday editing
  // works with the network off. See docs/OFFLINE.md.
  async function primeCache() {
    setBusy(true);
    setStatus("Priming offline cache…");
    try {
      const ms = await invoke<number>("warmup_cache");
      setStatus(`Cache primed in ${ms} ms`);
      setMissing(null);
      await build(source);
    } catch (e) {
      // Priming is never dropped as superseded, so anything caught here is real.
      setStatus(`Priming failed: ${(e as CompileErr).message ?? e}`);
    } finally {
      setBusy(false);
    }
  }

  async function toggleOffline() {
    const next = !offline;
    setOffline(next);
    await invoke("set_offline", { offline: next });
  }

  function requestExport() {
    if (screen !== "editor") return;
    if (pdf) setExportOpen(true);
    else setStatus("Nothing to export yet");
  }

  function edit(next: string) {
    setSource(next);
    setDirty(true);
  }

  function applyFix(fix: Fix) {
    editor.current?.replaceOnLine(fix.line, fix.find, fix.replace);
    setStatus(fix.label);
  }

  function insert(text: string) {
    // "Turn the selection into a table" is the one suggestion whose output
    // depends on what is selected, so it is built here rather than in the
    // catalogue.
    if (text === "" && selection) {
      const table = selectionToTable(selection);
      if (table) return editor.current?.insert(table);
      setStatus("That selection is not rows of separated values");
      return;
    }
    editor.current?.insert(text);
  }

  /* ── commands ─────────────────────────────────────────────────────────── */

  const commands = useMemo<AppCommand[]>(() => [
    { id: "save", title: "Save", hint: "⌘S", words: ["write", "disk"], run: () => saveFile(), disabled: !dirty && !!path },
    { id: "saveas", title: "Save as…", hint: "⇧⌘S", words: ["copy", "rename"], run: () => saveFile(true) },
    { id: "export", title: "Export as PDF…", hint: "⌘E", words: ["pdf", "save", "print"], run: () => setExportOpen(true), disabled: !pdf },
    { id: "open", title: "Open…", hint: "⌘O", words: ["file", "document"], run: openFile },
    { id: "new", title: "New document", hint: "⌘N", words: ["blank", "start"], run: () => adopt(ARTICLE, null, "New document") },
    { id: "build", title: "Set now", hint: "⌘R", words: ["build", "compile", "typeset", "rebuild"], run: () => build(source), disabled: busy },
    { id: "live", title: autoBuild ? "Stop setting as I type" : "Set as I type", words: ["live", "auto", "rebuild", "debounce"], run: () => setAutoBuild((v) => !v) },
    { id: "offline", title: offline ? "Allow the network" : "Refuse the network", words: ["offline", "online", "cache"], run: toggleOffline },
    { id: "zoomin", title: "Enlarge the proof", hint: "⌘+", words: ["zoom", "bigger"], run: () => setZoom((z) => Math.min(3, z + 0.15)) },
    { id: "zoomout", title: "Reduce the proof", hint: "⌘−", words: ["zoom", "smaller"], run: () => setZoom((z) => Math.max(0.5, z - 0.15)) },
    { id: "marks", title: "Show the marks", words: ["errors", "warnings", "problems", "proof"], run: () => setRightPane("marks"), disabled: visible.length === 0 },
    { id: "presslog", title: pressOpen ? "Hide the press log" : "Show the press log", words: ["log", "tex", "passes"], run: () => setPressOpen((v) => !v) },
    { id: "welcome", title: "Back to the title page", words: ["welcome", "home", "recent"], run: () => setScreen("welcome") },
    { id: "prime", title: "Prime the offline cache", words: ["download", "packages", "fonts"], run: primeCache, disabled: busy },
  ], [dirty, path, pdf, busy, autoBuild, offline, source, visible.length, pressOpen, adopt, build]);

  // Keyboard shortcuts. Held in a ref so the listener always calls the current
  // closure without rebinding on every keystroke.
  const hotkeys = useRef({ saveFile, requestExport, build, source, screen, adopt, openFile });
  hotkeys.current = { saveFile, requestExport, build, source, screen, adopt, openFile };
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (!(e.metaKey || e.ctrlKey)) return;
      const h = hotkeys.current;
      const k = e.key.toLowerCase();

      if (k === "k") { e.preventDefault(); setPaletteOpen((v) => !v); return; }
      if (k === "o") { e.preventDefault(); h.openFile(); return; }
      if (k === "n") { e.preventDefault(); h.adopt(ARTICLE, null, "New document"); return; }
      if (h.screen !== "editor") return;

      if (k === "s") { e.preventDefault(); h.saveFile(e.shiftKey); }        // ⇧ forces Save As
      else if (k === "r") { e.preventDefault(); h.build(h.source); }
      else if (k === "b") { e.preventDefault(); insert(`\\textbf{${CARET}}`); }
      else if (k === "i") { e.preventDefault(); insert(`\\emph{${CARET}}`); }
      else if (k === "=" || k === "+") { e.preventDefault(); setZoom((z) => Math.min(3, z + 0.15)); }
      else if (k === "-") { e.preventDefault(); setZoom((z) => Math.max(0.5, z - 0.15)); }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  // ⌘E is the File menu's accelerator, so it arrives here rather than as a
  // keydown.
  useEffect(() => {
    const pending = listen<string>("menu", (e) => {
      if (e.payload === "export") hotkeys.current.requestExport();
    });
    return () => { pending.then((unlisten) => unlisten()); };
  }, []);

  // Confirm before discarding unsaved work.
  //
  // `beforeunload` does not stop a native window close in a Tauri webview — no
  // dialog appears and the edits are simply gone — so the guard hangs off
  // Tauri's own close-requested event. Once a listener is registered Tauri
  // holds the close and destroys the window only if the handler lets it, so
  // cancelling means calling preventDefault. ⌘Q arrives here too; see
  // `build_menu` in lib.rs for why that needs help.
  const unsaved = useRef({ dirty, name });
  unsaved.current = { dirty, name };
  useEffect(() => {
    const pending = getCurrentWindow().onCloseRequested(async (e) => {
      if (!unsaved.current.dirty) return;
      const discard = await confirm(
        `"${unsaved.current.name}" has unsaved changes. They will be lost.`,
        { title: "Close without saving?", kind: "warning", okLabel: "Discard", cancelLabel: "Cancel" }
      );
      if (!discard) e.preventDefault();
    });
    return () => { pending.then((unlisten) => unlisten()); };
  }, []);

  /* ── render ───────────────────────────────────────────────────────────── */

  const palette = paletteOpen && (
    <Palette
      commands={commands}
      hasSelection={selection.length > 0}
      onInsert={insert}
      onClose={() => { setPaletteOpen(false); editor.current?.focus(); }}
    />
  );

  if (screen === "welcome") {
    return (
      <>
        <Welcome
          recent={recent}
          onNew={() => adopt(ARTICLE, null, "New document")}
          onOpen={openFile}
          onOpenRecent={openRecent}
          onPlate={(p: Plate) => adopt(p.source, null, `${p.name} plate`)}
          onSearch={() => setPaletteOpen(true)}
        />
        {palette}
      </>
    );
  }

  return (
    <div className="screen">
      <TitleBar
        title={`${name}${dirty ? " ·" : ""}`}
        right={
          <button className="lamp" onClick={toggleOffline}
            title={offline ? "The engine refuses all network access" : "The engine may fetch missing resources"}>
            <span className={`lamp-dot${offline ? "" : " is-open"}`} />
            {offline ? "Offline" : "Network"}
          </button>
        }
      />

      {missing && (
        <div className="banner">
          <span><code>{missing}</code> is not in the offline cache.</span>
          <button className="btn btn-sm btn-primary" onClick={() => build(source, true)} disabled={busy}>Fetch it</button>
          <button className="btn btn-sm" onClick={primeCache} disabled={busy}>Prime full cache</button>
          <span className="banner-note">both need the network, once</span>
        </div>
      )}

      <div className="spread">
        <nav className="contents">
          <div className="rubric">Contents</div>
          <div className="contents-list">
            {sections.map((s, i) => (
              <button
                key={`${s.line}-${i}`}
                className="contents-item"
                style={{ paddingLeft: 9 + (s.level - baseLevel) * 11 }}
                onClick={() => editor.current?.goto(s.line)}
                title={`line ${s.line}`}
              >
                <span className="contents-num tnum">{i + 1}</span>
                <span className="contents-title">{s.title}</span>
              </button>
            ))}
            {sections.length === 0 && <div className="contents-empty">No sections yet</div>}
          </div>

          <div className="hairline" />
          <div className="contents-tally">
            {tally.sections} section{tally.sections === 1 ? "" : "s"} · {tally.equations} equation{tally.equations === 1 ? "" : "s"}
            <br />
            {tally.citations} citation{tally.citations === 1 ? "" : "s"}
          </div>

          <div className="contents-foot">
            <span className={`state-dot${dirty ? " is-dirty" : ""}`} />
            <span className="contents-state">{dirty ? "Unsaved changes" : "Saved"}</span>
          </div>
        </nav>

        <section className="source">
          <Editor
            ref={editor}
            doc={source}
            docKey={docKey}
            onChange={edit}
            onSelection={setSelection}
          />
        </section>

        <div className="gutter" />

        <section className="recto">
          <div className="recto-tabs">
            <button
              className={`recto-tab${rightPane === "proof" ? " is-on" : ""}`}
              onClick={() => setRightPane("proof")}
            >
              Proof
            </button>
            <button
              className={`recto-tab${rightPane === "marks" ? " is-on" : ""}`}
              onClick={() => setRightPane("marks")}
              disabled={visible.length === 0}
            >
              Marks{visible.length > 0 && ` · ${visible.length}`}
            </button>
            <button
              className="btn btn-sm recto-export"
              onClick={() => setExportOpen(true)}
              disabled={!pdf || busy}
              title="Export as PDF (⌘E)"
            >
              Export PDF
            </button>
          </div>

          {rightPane === "proof" ? (
            <PdfView data={pdf} zoom={zoom} onPages={setPages} onPage={setPage} />
          ) : (
            <Marks
              diags={visible}
              built={!!pdf}
              onGoto={(l) => editor.current?.goto(l)}
              onFix={applyFix}
              onIgnore={(d) => setIgnored((ids) => [...ids, markKey(d)])}
            />
          )}

          <div className="recto-foot tnum">
            <span>
              {pages > 0 ? `Page ${Math.min(page, pages)} of ${pages}` : "No proof yet"}
              {" · "}{Math.round(zoom * 100)}%
            </span>
            <span className={busy ? "is-working" : undefined}>{status}</span>
          </div>
        </section>
      </div>

      <PressLog
        rows={press}
        durationMs={buildMs}
        open={pressOpen}
        onToggle={() => setPressOpen((v) => !v)}
      />

      {exportOpen && pdf && (
        <ExportSheet
          pdf={pdf}
          name={name}
          docSheet={sheetOf(source)}
          durationMs={buildMs}
          busy={busy}
          onExport={runExport}
          onClose={() => setExportOpen(false)}
        />
      )}

      {palette}
    </div>
  );
}
