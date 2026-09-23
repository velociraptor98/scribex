import { useEffect, useState } from "react";
import * as pdfjs from "pdfjs-dist";
import { ExportOptions, SHEETS, Sheet } from "./exporting";

interface Props {
  /** Bytes of the last successful build; the thumbnails are rendered from these. */
  pdf: Uint8Array;
  name: string;
  /** Paper size the document currently declares. */
  docSheet: Sheet;
  /** Wall-clock time of the build that produced `pdf`. */
  durationMs?: number;
  busy: boolean;
  onExport: (opts: ExportOptions) => void;
  onClose: () => void;
}

export default function ExportSheet({
  pdf, name, docSheet, durationMs, busy, onExport, onClose,
}: Props) {
  const [sheet, setSheet] = useState<Sheet>(docSheet);
  const [hyperlinks, setHyperlinks] = useState(false);
  const [sourceAlongside, setSourceAlongside] = useState(false);
  const { pages, thumbs } = useThumbnails(pdf);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const stem = name.replace(/\.tex$/i, "");

  return (
    <div className="scrim" onMouseDown={onClose}>
      <div className="imprint" onMouseDown={(e) => e.stopPropagation()} role="dialog" aria-label="Export">
        <div className="imprint-head">
          <h2 className="imprint-title">Export</h2>
          <p className="imprint-sub">
            {stem}.pdf
            {pages > 0 && ` · ${pages} page${pages > 1 ? "s" : ""}`}
          </p>
        </div>

        <div className="hairline" />

        <div className="imprint-body">
          <div className="imprint-thumbs">
            {thumbs.map((src, i) => (
              <img className="imprint-thumb" key={i} src={src} alt={`Page ${i + 1}`} />
            ))}
            {thumbs.length === 0 && <div className="imprint-thumb is-blank" />}
          </div>

          <div className="imprint-options">
            <div>
              <div className="imprint-label">Sheet</div>
              <div className="seg">
                {SHEETS.map((s) => (
                  <button
                    key={s.id}
                    className={`seg-opt${sheet === s.id ? " is-on" : ""}`}
                    onClick={() => setSheet(s.id)}
                  >
                    {s.label}
                  </button>
                ))}
              </div>
            </div>

            <div className="imprint-checks">
              <Check on={hyperlinks} set={setHyperlinks} label="Hyperlinked cross-references" />
              <Check on={sourceAlongside} set={setSourceAlongside} label="Save the source .tex alongside" />
            </div>

            {sheet !== docSheet && (
              <p className="imprint-note">
                The document is set on {SHEETS.find((s) => s.id === docSheet)!.label}.
                Exporting will re-typeset it on {SHEETS.find((s) => s.id === sheet)!.label};
                your file is not changed.
              </p>
            )}
          </div>
        </div>

        <div className="imprint-foot">
          <span className="tnum">
            {size(pdf.byteLength)}
            {durationMs !== undefined && ` · ${durationMs} ms to set`}
          </span>
          <div className="imprint-actions">
            <button className="btn" onClick={onClose}>Cancel</button>
            <button
              className="btn btn-primary"
              disabled={busy}
              onClick={() => onExport({ sheet, hyperlinks, sourceAlongside })}
            >
              {busy ? "Building…" : "Export PDF"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

/** Most PDFs here are tens of kilobytes; "0.02 MB" tells the reader nothing. */
function size(bytes: number): string {
  return bytes < 1024 * 1024
    ? `${Math.round(bytes / 1024)} KB`
    : `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function Check({
  on, set, label,
}: { on: boolean; set: (v: boolean) => void; label: string }) {
  return (
    <button className={`check${on ? " is-on" : ""}`} onClick={() => set(!on)} role="checkbox" aria-checked={on}>
      <span className="check-box">{on ? "✓" : ""}</span>
      {label}
    </button>
  );
}

/** Render the first pages of the built PDF as data URLs for the sheet. */
function useThumbnails(pdf: Uint8Array) {
  const [pages, setPages] = useState(0);
  const [thumbs, setThumbs] = useState<string[]>([]);

  useEffect(() => {
    let cancelled = false;
    // pdf.js neuters the buffer it is handed, so give it a copy.
    const task = pdfjs.getDocument({ data: pdf.slice() });

    (async () => {
      try {
        const doc = await task.promise;
        if (cancelled) return;
        setPages(doc.numPages);

        const out: string[] = [];
        for (let n = 1; n <= Math.min(2, doc.numPages); n++) {
          const page = await doc.getPage(n);
          if (cancelled) return;
          // Fixed height, so Letter and A5 thumbnails stack to the same measure.
          const base = page.getViewport({ scale: 1 });
          const viewport = page.getViewport({ scale: (96 * 2) / base.height });
          const canvas = document.createElement("canvas");
          canvas.width = Math.ceil(viewport.width);
          canvas.height = Math.ceil(viewport.height);
          const ctx = canvas.getContext("2d")!;
          await page.render({ canvas, canvasContext: ctx, viewport }).promise;
          if (cancelled) return;
          out.push(canvas.toDataURL());
        }
        if (!cancelled) setThumbs(out);
      } catch {
        // A thumbnail is a courtesy; the export itself does not depend on it.
      }
    })();

    return () => { cancelled = true; task.destroy(); };
  }, [pdf]);

  return { pages, thumbs };
}
