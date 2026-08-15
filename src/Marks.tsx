/** 1d — errors as marginalia: a proof-reader's slip, plus the press log. */

import { Diagnostic, Fix, PressRow } from "./texlog";

interface MarksProps {
  diags: Diagnostic[];
  /** True once a build has completed, so "set cleanly" is a claim we can make. */
  built: boolean;
  onGoto: (line: number) => void;
  onFix: (fix: Fix) => void;
  onIgnore: (diag: Diagnostic) => void;
}

export function Marks({ diags, built, onGoto, onFix, onIgnore }: MarksProps) {
  return (
    <aside className="marks">
      <div className="rubric">Marks on this proof</div>

      {diags.map((d, i) => (
        <article className="mark" key={`${d.title}-${d.line ?? i}`}>
          <button
            className="mark-line tnum"
            onClick={() => d.line && onGoto(d.line)}
            disabled={!d.line}
            title={d.line ? `Go to line ${d.line}` : undefined}
          >
            {d.line ? `l. ${d.line}` : "—"}
          </button>

          <div className="mark-body">
            <h3 className={`mark-title${d.severity === "error" ? " is-error" : ""}`}>
              {d.title}
            </h3>
            {d.detail && <p className="mark-detail">{d.detail}</p>}

            {/* TeX's own wording, for anything the translation flattened. */}
            {d.detail && d.raw !== d.title && (
              <p className="mark-raw selectable" title="What TeX said">{d.raw}</p>
            )}

            <div className="mark-actions">
              {(d.fixes ?? []).map((f) => (
                <button key={f.label} className="btn btn-primary btn-sm" onClick={() => onFix(f)}>
                  {f.label}
                </button>
              ))}
              <button className="btn btn-sm" onClick={() => onIgnore(d)}>Ignore</button>
            </div>
          </div>
        </article>
      ))}

      {diags.length === 0 && (
        <p className="marks-clean">
          {built ? "Everything set cleanly." : "Nothing set yet."}
        </p>
      )}

      {diags.length > 0 && (
        <p className="marks-clean">Everything else set cleanly.</p>
      )}
    </aside>
  );
}

interface PressProps {
  rows: PressRow[];
  /** Wall-clock time for the whole run, straight from the engine. */
  durationMs?: number;
  open: boolean;
  onToggle: () => void;
}

export function PressLog({ rows, durationMs, open, onToggle }: PressProps) {
  return (
    <section className={`presslog${open ? " is-open" : ""}`}>
      <button className="presslog-head" onClick={onToggle}>
        <span className="rubric">Press log</span>
        <span className="presslog-meta tnum">
          Tectonic
          {durationMs !== undefined && ` · ${(durationMs / 1000).toFixed(2)} s`}
          <span className="presslog-caret">{open ? "▾" : "▸"}</span>
        </span>
      </button>

      {open && (
        <div className="presslog-rows">
          {rows.map((r) => (
            <div className="presslog-row" key={r.stage}>
              <span>{r.stage}</span>
              <span className={r.flagged ? "is-flagged" : "is-quiet"}>{r.detail}</span>
            </div>
          ))}
          {rows.length === 0 && <div className="presslog-row"><span>—</span><span className="is-quiet">no run yet</span></div>}
        </div>
      )}
    </section>
  );
}
