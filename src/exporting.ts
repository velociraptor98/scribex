/**
 * Making the imprint sheet's options real.
 *
 * The engine copies whatever the last build produced, so an export option only
 * means something if it changes the document that gets built. Both options here
 * do that by rewriting the source for one throwaway build — the buffer on
 * screen and the file on disk are never touched.
 */

export type Sheet = "letter" | "a4" | "a5";

export const SHEETS: { id: Sheet; label: string; option: string }[] = [
  { id: "letter", label: "Letter", option: "letterpaper" },
  { id: "a4", label: "A4", option: "a4paper" },
  { id: "a5", label: "A5", option: "a5paper" },
];

const PAPER_OPTION = /^(?:a[0-6]|b[0-6]|ansi[a-e]|letter|legal|executive)paper$/i;
const DOCUMENTCLASS = /\\documentclass(\s*\[([^\]]*)\])?\s*\{([^}]+)\}/;

/**
 * Set the paper size as a *class* option rather than a `geometry` one.
 *
 * geometry reads the class option, so this works whether or not the document
 * loads geometry — and it cannot raise the option clash that a second
 * `\usepackage[a4paper]{geometry}` would in a document that already loads it.
 */
export function withSheet(source: string, sheet: Sheet): string {
  const wanted = SHEETS.find((s) => s.id === sheet)!.option;
  const m = DOCUMENTCLASS.exec(source);
  if (!m) return source;

  const opts = (m[2] ?? "")
    .split(",")
    .map((o) => o.trim())
    .filter((o) => o && !PAPER_OPTION.test(o));
  opts.push(wanted);

  return source.replace(DOCUMENTCLASS, `\\documentclass[${opts.join(",")}]{${m[3]}}`);
}

/** Load hyperref, unless the document already does. Last in the preamble is
 *  where it wants to be — it redefines a great deal on the way in. */
export function withHyperref(source: string): string {
  if (/\\usepackage(\[[^\]]*\])?\{[^}]*\bhyperref\b[^}]*\}/.test(source)) return source;
  const at = source.indexOf("\\begin{document}");
  if (at < 0) return source;
  return source.slice(0, at) + "\\usepackage{hyperref}\n" + source.slice(at);
}

export interface ExportOptions {
  sheet: Sheet;
  hyperlinks: boolean;
  /** Write the .tex next to the PDF. */
  sourceAlongside: boolean;
}

export function needsRebuild(o: ExportOptions, docSheet: Sheet): boolean {
  return o.sheet !== docSheet || o.hyperlinks;
}

export function applyOptions(source: string, o: ExportOptions): string {
  let out = withSheet(source, o.sheet);
  if (o.hyperlinks) out = withHyperref(out);
  return out;
}

/** The paper size the document already declares, so the sheet control opens on
 *  the truth rather than on a guess. */
export function sheetOf(source: string): Sheet {
  const m = DOCUMENTCLASS.exec(source);
  const opts = (m?.[2] ?? "").split(",").map((o) => o.trim().toLowerCase());
  for (const s of SHEETS) if (opts.includes(s.option)) return s.id;
  // article/report/book default to US Letter.
  return "letter";
}
