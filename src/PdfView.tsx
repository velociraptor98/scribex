import { useEffect, useRef, useState } from "react";
import * as pdfjs from "pdfjs-dist";
import workerUrl from "pdfjs-dist/build/pdf.worker.mjs?url";

pdfjs.GlobalWorkerOptions.workerSrc = workerUrl;

/** A fixed scale, or whatever makes the widest page fill the pane. */
export type Zoom = number | "fit";

export const MIN_ZOOM = 0.25;
export const MAX_ZOOM = 4;
const STEPS = [0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4];

/** The next stop up or down from `scale`, which may be an odd fit-width value. */
export function stepZoom(scale: number, dir: 1 | -1): number {
  const next = dir > 0
    ? STEPS.find((s) => s > scale + 0.005)
    : [...STEPS].reverse().find((s) => s < scale - 0.005);
  return next ?? (dir > 0 ? MAX_ZOOM : MIN_ZOOM);
}

// The plate's 7px border each side, plus its 1px outline.
const PLATE = 16;

interface Props {
  /** Raw PDF bytes; null before the first successful build. */
  data: Uint8Array | null;
  zoom: Zoom;
  /** The scale actually rendered, so "fit" can be shown and stepped from. */
  onScale?: (scale: number) => void;
  /** Page count and the page in view, for the footer under the preview. */
  onPages?: (total: number) => void;
  onPage?: (current: number) => void;
}

/** Where the reader is, as a page and a fraction down it, so it survives a change of scale. */
function placeOf(el: HTMLElement) {
  const pages = Array.from(el.querySelectorAll<HTMLElement>(".page"));
  const top = el.scrollTop;
  let i = 0;
  while (i < pages.length - 1 && pages[i + 1].offsetTop <= top) i++;
  const p = pages[i];
  return {
    page: i,
    frac: p ? (top - p.offsetTop) / p.offsetHeight : 0,
    across: el.scrollWidth > el.clientWidth
      ? (el.scrollLeft + el.clientWidth / 2) / el.scrollWidth
      : 0.5,
  };
}

function restore(el: HTMLElement, at: ReturnType<typeof placeOf>) {
  const pages = el.querySelectorAll<HTMLElement>(".page");
  const p = pages[Math.min(at.page, pages.length - 1)];
  if (p) el.scrollTop = p.offsetTop + at.frac * p.offsetHeight;
  el.scrollLeft = at.across * el.scrollWidth - el.clientWidth / 2;
}

export default function PdfView({ data, zoom, onScale, onPages, onPage }: Props) {
  const host = useRef<HTMLDivElement>(null);
  const [error, setError] = useState<string | null>(null);
  const report = useRef({ onScale, onPages, onPage });
  report.current = { onScale, onPages, onPage };
  // The scale on screen now, so a zoom can stretch it at once while the
  // sharp render catches up.
  const shown = useRef(0);

  // Fit-to-width follows the pane. Settle before re-rendering: a drag of the
  // window would otherwise typeset every page on every frame.
  const [width, setWidth] = useState(0);
  useEffect(() => {
    const el = host.current;
    if (!el) return;
    let timer: ReturnType<typeof setTimeout>;
    let first = true;
    const ro = new ResizeObserver(() => {
      clearTimeout(timer);
      timer = setTimeout(() => setWidth(el.clientWidth), first ? 0 : 120);
      first = false;
    });
    ro.observe(el);
    return () => { ro.disconnect(); clearTimeout(timer); };
  }, []);
  const fitWidth = zoom === "fit" ? width : 0;

  useEffect(() => {
    if (!data || !host.current) return;
    if (zoom === "fit" && !fitWidth) return;
    const el = host.current;
    let cancelled = false;
    // Keep the loading task, not the document: teardown lives on the task.
    let task: pdfjs.PDFDocumentLoadingTask | null = null;

    (async () => {
      try {
        // pdf.js transfers and neuters the buffer, so hand it a copy.
        task = pdfjs.getDocument({ data: data.slice() });
        const doc = await task.promise;
        if (cancelled) return;
        report.current.onPages?.(doc.numPages);

        const pages: pdfjs.PDFPageProxy[] = [];
        for (let n = 1; n <= doc.numPages; n++) pages.push(await doc.getPage(n));
        if (cancelled) return;

        let scale = zoom as number;
        if (zoom === "fit") {
          const widest = Math.max(...pages.map((p) => p.getViewport({ scale: 1 }).width));
          scale = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, (fitWidth - PLATE) / widest));
        }
        report.current.onScale?.(scale);

        // Stretch what's already there so the zoom is felt immediately.
        if (shown.current && Math.abs(scale - shown.current) > 0.001) {
          const ratio = scale / shown.current;
          const at = placeOf(el);
          for (const c of el.querySelectorAll<HTMLElement>(".page")) {
            c.style.width = `${parseFloat(c.style.width) * ratio}px`;
            c.style.height = `${parseFloat(c.style.height) * ratio}px`;
          }
          shown.current = scale;
          restore(el, at);
        }

        const frag = document.createDocumentFragment();
        const dpr = window.devicePixelRatio || 1;

        for (const [i, page] of pages.entries()) {
          const viewport = page.getViewport({ scale });
          const canvas = document.createElement("canvas");
          canvas.className = "page plate";
          canvas.dataset.page = String(i + 1);
          canvas.width = Math.floor(viewport.width * dpr);
          canvas.height = Math.floor(viewport.height * dpr);
          canvas.style.width = `${Math.floor(viewport.width)}px`;
          canvas.style.height = `${Math.floor(viewport.height)}px`;
          const ctx = canvas.getContext("2d")!;
          ctx.scale(dpr, dpr);
          await page.render({ canvas, canvasContext: ctx, viewport }).promise;
          if (cancelled) return;
          frag.appendChild(canvas);
        }

        // Preserve the reading position across recompiles and zooms —
        // otherwise every keystroke throws the reader back to page 1.
        const at = placeOf(el);
        el.replaceChildren(frag);
        shown.current = scale;
        restore(el, at);
        setError(null);
      } catch (e) {
        if (!cancelled) setError(String(e));
      }
    })();

    return () => {
      cancelled = true;
      task?.destroy();
    };
  }, [data, zoom, fitWidth]);

  /** Whichever page covers the middle of the well is the one being read. */
  function trackPage(el: HTMLDivElement) {
    const mid = el.scrollTop + el.clientHeight / 2;
    let current = 1;
    for (const c of Array.from(el.querySelectorAll<HTMLElement>(".page"))) {
      if (c.offsetTop <= mid) current = Number(c.dataset.page ?? current);
      else break;
    }
    report.current.onPage?.(current);
  }

  return (
    <div className="pdf" ref={host} onScroll={(e) => trackPage(e.currentTarget)}>
      {error && <div className="pdf-error selectable">{error}</div>}
      {!data && !error && <div className="pdf-empty">Nothing built yet</div>}
    </div>
  );
}
