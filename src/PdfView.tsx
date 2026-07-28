import { useEffect, useRef, useState } from "react";
import * as pdfjs from "pdfjs-dist";
import workerUrl from "pdfjs-dist/build/pdf.worker.mjs?url";

pdfjs.GlobalWorkerOptions.workerSrc = workerUrl;

interface Props {
  /** Raw PDF bytes; null before the first successful build. */
  data: Uint8Array | null;
  zoom: number;
}

export default function PdfView({ data, zoom }: Props) {
  const host = useRef<HTMLDivElement>(null);
  const [error, setError] = useState<string | null>(null);
  // Preserve scroll position across recompiles — otherwise every keystroke
  // throws the reader back to page 1, which makes live preview unusable.
  const scroll = useRef(0);

  useEffect(() => {
    if (!data || !host.current) return;
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

        const prev = scroll.current;
        const frag = document.createDocumentFragment();
        const dpr = window.devicePixelRatio || 1;

        for (let n = 1; n <= doc.numPages; n++) {
          const page = await doc.getPage(n);
          if (cancelled) return;
          const viewport = page.getViewport({ scale: zoom });
          const canvas = document.createElement("canvas");
          canvas.className = "page";
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

        el.replaceChildren(frag);
        el.scrollTop = prev;
        setError(null);
      } catch (e) {
        if (!cancelled) setError(String(e));
      }
    })();

    return () => {
      cancelled = true;
      task?.destroy();
    };
  }, [data, zoom]);

  return (
    <div
      className="pdf"
      ref={host}
      onScroll={(e) => (scroll.current = e.currentTarget.scrollTop)}
    >
      {error && <div className="pdf-error">{error}</div>}
      {!data && !error && <div className="pdf-empty">No output yet</div>}
    </div>
  );
}
