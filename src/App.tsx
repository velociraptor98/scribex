import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import { readTextFile, mkdir } from "@tauri-apps/plugin-fs";
import { appLocalDataDir } from "@tauri-apps/api/path";
import Editor from "./Editor";
import PdfView from "./PdfView";
import { outline } from "./latex";
import { parseLog, Diagnostic } from "./texlog";
import "./App.css";

interface CompileOk { pdf: number[]; log: string; duration_ms: number }
interface CompileErr { message: string; log: string; missing_file: string | null; duration_ms: number }

const SAMPLE = `\\documentclass{article}
\\title{ScribeX}
\\author{}
\\date{}
\\begin{document}
\\maketitle

\\section{Offline by default}
This document was typeset locally by Tectonic, with no network access.

\\section{Mathematics}
\\begin{equation}
  \\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}
\\end{equation}

\\end{document}
`;

const DEBOUNCE_MS = 600;

export default function App() {
  const [source, setSource] = useState(SAMPLE);
  const [path, setPath] = useState<string | null>(null);
  const [pdf, setPdf] = useState<Uint8Array | null>(null);
  const [diags, setDiags] = useState<Diagnostic[]>([]);
  const [status, setStatus] = useState("Ready");
  const [busy, setBusy] = useState(false);
  const [offline, setOffline] = useState(true);
  const [missing, setMissing] = useState<string | null>(null);
  const [zoom, setZoom] = useState(1.3);
  const [goto, setGoto] = useState<number | undefined>();
  const [autoBuild, setAutoBuild] = useState(true);

  // Scratch file used until the user opens or saves a real document.
  const scratchPath = useRef<string | null>(null);
  const seq = useRef(0);

  const sections = useMemo(() => outline(source), [source]);

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
        setPdf(new Uint8Array(r.pdf));
        setDiags(parseLog(r.log));
        setMissing(null);
        setStatus(`Built in ${r.duration_ms} ms`);
      } catch (e) {
        if (mine !== seq.current) return;
        const err = e as CompileErr;
        setDiags(parseLog(err.log ?? ""));
        setMissing(err.missing_file ?? null);
        setStatus(err.missing_file ? `Missing package: ${err.missing_file}` : "Build failed");
      } finally {
        if (mine === seq.current) setBusy(false);
      }
    },
    [path]
  );

  // Resolve a scratch path once, then do the initial build.
  useEffect(() => {
    (async () => {
      const dir = await appLocalDataDir();
      await mkdir(dir, { recursive: true }).catch(() => {});
      scratchPath.current = `${dir}/scratch.tex`;
      await invoke("set_offline", { offline: true });
      build(SAMPLE);
    })();
  }, []);

  // Debounced live rebuild.
  useEffect(() => {
    if (!autoBuild) return;
    const t = setTimeout(() => build(source), DEBOUNCE_MS);
    return () => clearTimeout(t);
  }, [source, autoBuild, build]);

  async function openFile() {
    const picked = await open({ filters: [{ name: "LaTeX", extensions: ["tex"] }] });
    if (typeof picked !== "string") return;
    const text = await readTextFile(picked);
    setPath(picked);
    setSource(text);
    setStatus(`Opened ${picked.split("/").pop()}`);
  }

  // One-time download of the common package/font set so that everyday editing
  // works with the network off. See docs/OFFLINE.md.
  async function primeCache() {
    setBusy(true);
    setStatus("Priming offline cache…");
    try {
      const dir = await appLocalDataDir();
      const ms = await invoke<number>("warmup_cache", { dir });
      setStatus(`Cache primed in ${ms} ms`);
      setMissing(null);
      await build(source);
    } catch (e) {
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

  const errors = diags.filter((d) => d.severity === "error");
  const warnings = diags.filter((d) => d.severity === "warning");

  return (
    <div className="app">
      <header className="bar">
        <strong>ScribeX</strong>
        <button onClick={openFile}>Open…</button>
        <button onClick={() => build(source)} disabled={busy}>Build</button>
        <label className="chk">
          <input type="checkbox" checked={autoBuild} onChange={(e) => setAutoBuild(e.target.checked)} />
          Live
        </label>
        <label className="chk" title="When on, the engine refuses all network access">
          <input type="checkbox" checked={offline} onChange={toggleOffline} />
          Offline
        </label>
        <span className="spacer" />
        <button onClick={() => setZoom((z) => Math.max(0.5, z - 0.15))}>−</button>
        <span className="zoom">{Math.round(zoom * 100)}%</span>
        <button onClick={() => setZoom((z) => Math.min(3, z + 0.15))}>+</button>
      </header>

      {missing && (
        <div className="banner">
          <span>
            <code>{missing}</code> is not in the offline cache.
          </span>
          <button onClick={() => build(source, true)} disabled={busy}>
            Fetch it
          </button>
          <button onClick={primeCache} disabled={busy}>
            Prime full cache
          </button>
          <span className="muted">(both need network, once)</span>
        </div>
      )}

      <div className="panes">
        <nav className="outline">
          <div className="outline-head">Outline</div>
          {sections.length === 0 && <div className="muted">No sections</div>}
          {sections.map((s, i) => (
            <button key={i} className="outline-item" style={{ paddingLeft: 8 + s.level * 12 }}
              onClick={() => setGoto(s.line)} title={`line ${s.line}`}>
              {s.title}
            </button>
          ))}
        </nav>

        <section className="pane">
          <Editor initial={source} onChange={setSource} gotoLine={goto} />
        </section>

        <section className="pane">
          <PdfView data={pdf} zoom={zoom} />
        </section>
      </div>

      <footer className="status">
        <span className={busy ? "pulse" : ""}>{status}</span>
        <span className="spacer" />
        {errors.length > 0 && <span className="err">{errors.length} error{errors.length > 1 ? "s" : ""}</span>}
        {warnings.length > 0 && <span className="warn">{warnings.length} warning{warnings.length > 1 ? "s" : ""}</span>}
      </footer>

      {diags.length > 0 && (
        <div className="diags">
          {diags.slice(0, 40).map((d, i) => (
            <button key={i} className={`diag ${d.severity}`}
              onClick={() => d.line && setGoto(d.line)}>
              <span className="sev">{d.severity === "error" ? "✕" : "!"}</span>
              {d.line && <span className="ln">{d.line}</span>}
              <span className="msg">{d.message}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
