/**
 * The ⌘K palette: plain English in, LaTeX out.
 *
 * Matching is a local keyword score — no model, no network. That is a design
 * constraint, not a shortcut: the palette's footer promises that nothing leaves
 * this machine, and an offline LaTeX editor that phones home to write a table
 * would be a poor joke. The vocabulary below is what makes it feel fluent, so
 * synonyms matter more here than clever ranking.
 */

/** Where the caret should land after an insertion. Stripped before insert. */
export const CARET = "\u2038";

export interface Suggestion {
  id: string;
  title: string;
  /** The LaTeX this will insert, elided for display. */
  preview?: string;
  /** A keyboard equivalent, when the action has one. */
  hint?: string;
  text?: string;
  run?: () => void;
  score: number;
}

interface Intent {
  id: string;
  /** Words that should pull this intent up. Stemmed loosely by prefix match. */
  words: string[];
  /**
   * Tie-break weight. Two intents often match a query equally well — "a table"
   * hits both `table` and `booktabs` — and the plainer reading should win
   * unless the query names the specialised one. Small enough that it never
   * overturns a genuinely better keyword match.
   */
  bias?: number;
  /** Built from the query so counts and names can flow into the title. */
  build: (q: Query) => { title: string; preview?: string; text: string; hint?: string };
}

interface Query {
  text: string;
  words: string[];
  /** First two integers in the query, e.g. "3 by 4" → [3, 4]. */
  nums: number[];
  hasSelection: boolean;
}

const cols = (q: Query) => clamp(q.nums[0] ?? 3, 1, 12);
const rows = (q: Query) => clamp(q.nums[1] ?? q.nums[0] ?? 3, 1, 40);
const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n));

function tabular(c: number, r: number, booktabs: boolean): string {
  const spec = "l".repeat(c);
  const row = (cell: string) => Array.from({ length: c }, (_, i) => `${cell}${i + 1}`).join(" & ");
  const body: string[] = [];
  body.push(`  ${row("Head")} \\\\`);
  body.push(booktabs ? "  \\midrule" : "  \\hline");
  for (let i = 0; i < r; i++) body.push(`  ${row("Cell")} \\\\`);
  return [
    "\\begin{tabular}{" + spec + "}",
    booktabs ? "  \\toprule" : "  \\hline",
    ...body,
    booktabs ? "  \\bottomrule" : "  \\hline",
    "\\end{tabular}" + CARET,
  ].join("\n");
}

const INTENTS: Intent[] = [
  {
    id: "table",
    words: ["table", "tabular", "grid", "rows", "columns", "cells", "spreadsheet", "matrix of"],
    bias: 0.03,
    build: (q) => {
      const c = cols(q), r = rows(q);
      return {
        title: `Insert a table — ${c} column${c > 1 ? "s" : ""} × ${r} row${r > 1 ? "s" : ""}`,
        preview: `\\begin{tabular}{${"l".repeat(c)}} … \\end{tabular}`,
        text: tabular(c, r, false),
      };
    },
  },
  {
    id: "booktabs",
    words: ["booktabs", "ruled", "professional", "toprule", "midrule", "table", "no verticals"],
    build: (q) => {
      const c = cols(q), r = rows(q);
      return {
        title: "Insert a booktabs table (ruled, no verticals)",
        preview: "\\usepackage{booktabs} · \\toprule … \\bottomrule",
        text: tabular(c, r, true),
      };
    },
  },
  {
    id: "caption",
    words: ["caption", "label", "title", "number", "reference", "cross"],
    build: () => ({
      title: "Add a caption and a label",
      preview: "\\caption{…} \\label{tab:…}",
      hint: "⌘⇧C",
      text: `\\caption{${CARET}}\n\\label{tab:key}`,
    }),
  },
  {
    id: "twocolumn",
    words: ["two", "column", "columns", "twocolumn", "double", "page", "layout"],
    build: () => ({
      title: "Set the page in two columns",
      preview: "\\documentclass[twocolumn]{…} · \\twocolumn",
      text: `\\twocolumn${CARET}`,
    }),
  },
  {
    id: "equation",
    words: ["equation", "maths", "math", "formula", "numbered", "display", "expression"],
    build: () => ({
      title: "Insert a numbered equation",
      preview: "\\begin{equation} … \\end{equation}",
      text: `\\begin{equation}\n  ${CARET}\n\\end{equation}`,
    }),
  },
  {
    id: "align",
    words: ["align", "aligned", "multiline", "several", "lines", "equations", "system"],
    build: () => ({
      title: "Insert aligned equations",
      preview: "\\begin{align} … \\end{align}",
      text: `\\begin{align}\n  ${CARET} &= \\\\\n   &=\n\\end{align}`,
    }),
  },
  {
    id: "figure",
    words: ["figure", "image", "picture", "graphic", "photo", "diagram", "includegraphics", "plot"],
    build: () => ({
      title: "Insert a figure with a caption",
      preview: "\\begin{figure} \\includegraphics … \\end{figure}",
      text: [
        "\\begin{figure}[htbp]",
        "  \\centering",
        `  \\includegraphics[width=0.8\\textwidth]{${CARET}}`,
        "  \\caption{}",
        "  \\label{fig:key}",
        "\\end{figure}",
      ].join("\n"),
    }),
  },
  {
    id: "itemize",
    words: ["bullet", "bullets", "list", "itemize", "unordered", "points", "dot"],
    build: () => ({
      title: "Insert a bulleted list",
      preview: "\\begin{itemize} \\item … \\end{itemize}",
      text: `\\begin{itemize}\n  \\item ${CARET}\n  \\item\n\\end{itemize}`,
    }),
  },
  {
    id: "enumerate",
    words: ["numbered", "list", "enumerate", "ordered", "steps", "count"],
    build: () => ({
      title: "Insert a numbered list",
      preview: "\\begin{enumerate} \\item … \\end{enumerate}",
      text: `\\begin{enumerate}\n  \\item ${CARET}\n  \\item\n\\end{enumerate}`,
    }),
  },
  {
    id: "section",
    words: ["section", "heading", "header", "chapter", "part", "title"],
    build: () => ({
      title: "Start a new section",
      preview: "\\section{…}",
      text: `\\section{${CARET}}`,
    }),
  },
  {
    id: "cite",
    words: ["cite", "citation", "reference", "bibliography", "source", "paper", "bibtex"],
    build: () => ({
      title: "Cite a work",
      preview: "\\cite{key}",
      text: `\\cite{${CARET}}`,
    }),
  },
  {
    id: "ref",
    words: ["ref", "reference", "refer", "cross", "link", "point", "equation", "figure"],
    build: () => ({
      title: "Refer to a label",
      preview: "\\ref{key}",
      text: `\\ref{${CARET}}`,
    }),
  },
  {
    id: "footnote",
    words: ["footnote", "note", "aside", "remark", "bottom"],
    build: () => ({
      title: "Add a footnote",
      preview: "\\footnote{…}",
      text: `\\footnote{${CARET}}`,
    }),
  },
  {
    id: "matrix",
    words: ["matrix", "matrices", "array", "bracket", "pmatrix", "determinant"],
    build: (q) => {
      const c = cols(q), r = rows(q);
      const body = Array.from({ length: r }, () =>
        Array.from({ length: c }, () => "0").join(" & ")
      ).join(" \\\\\n  ");
      return {
        title: `Insert a ${c} × ${r} matrix`,
        preview: "\\begin{pmatrix} … \\end{pmatrix}",
        text: `\\begin{pmatrix}\n  ${body}\n\\end{pmatrix}${CARET}`,
      };
    },
  },
  {
    id: "verbatim",
    words: ["code", "verbatim", "listing", "monospace", "program", "snippet"],
    build: () => ({
      title: "Insert a code block",
      preview: "\\begin{verbatim} … \\end{verbatim}",
      text: `\\begin{verbatim}\n${CARET}\n\\end{verbatim}`,
    }),
  },
  {
    id: "quote",
    words: ["quote", "quotation", "block", "excerpt", "indent"],
    build: () => ({
      title: "Insert a block quotation",
      preview: "\\begin{quote} … \\end{quote}",
      text: `\\begin{quote}\n  ${CARET}\n\\end{quote}`,
    }),
  },
  {
    id: "bold",
    words: ["bold", "strong", "heavy", "textbf", "emphasis"],
    build: (q) => ({
      title: q.hasSelection ? "Set the selection in bold" : "Set text in bold",
      preview: "\\textbf{…}",
      hint: "⌘B",
      text: `\\textbf{${CARET}}`,
    }),
  },
  {
    id: "italic",
    words: ["italic", "italics", "emphasise", "emphasize", "emph", "slanted"],
    build: (q) => ({
      title: q.hasSelection ? "Set the selection in italics" : "Set text in italics",
      preview: "\\emph{…}",
      hint: "⌘I",
      text: `\\emph{${CARET}}`,
    }),
  },
  {
    id: "toc",
    words: ["contents", "toc", "tableofcontents", "outline", "index"],
    build: () => ({
      title: "Insert a table of contents",
      preview: "\\tableofcontents",
      text: `\\tableofcontents${CARET}`,
    }),
  },
  {
    id: "abstract",
    words: ["abstract", "summary", "synopsis"],
    build: () => ({
      title: "Insert an abstract",
      preview: "\\begin{abstract} … \\end{abstract}",
      text: `\\begin{abstract}\n  ${CARET}\n\\end{abstract}`,
    }),
  },
  {
    id: "package",
    words: ["package", "usepackage", "import", "library", "load"],
    build: () => ({
      title: "Load a package",
      preview: "\\usepackage{…}",
      text: `\\usepackage{${CARET}}`,
    }),
  },
  {
    id: "pagebreak",
    words: ["page", "break", "newpage", "clearpage", "next"],
    build: () => ({
      title: "Break to a new page",
      preview: "\\newpage",
      text: `\\newpage${CARET}`,
    }),
  },
];

/** Selection-aware variants, offered only when there is something selected. */
const WRAPPERS: Intent[] = [
  {
    id: "wrap-table",
    words: ["table", "turn", "convert", "selection", "into", "make"],
    build: () => ({
      title: "Turn the selection into a table",
      preview: "rows of tab- or comma-separated text → tabular",
      text: "",
    }),
  },
];

export function tokenize(s: string): string[] {
  return s.toLowerCase().split(/[^a-z0-9]+/).filter((w) => w.length > 1 && !STOP.has(w));
}

// Filler that would otherwise match everything.
const STOP = new Set([
  "the", "and", "for", "with", "put", "add", "insert", "make", "give", "get",
  "here", "there", "this", "that", "please", "can", "you", "would", "like",
  "want", "need", "some", "into", "onto", "new", "one",
]);

function scoreIntent(intent: Intent, words: string[]): number {
  if (words.length === 0) return 0;
  let hits = 0;
  for (const w of words) {
    for (const k of intent.words) {
      if (k === w) { hits += 2; break; }
      if (k.startsWith(w) || w.startsWith(k)) { hits += 1; break; }
    }
  }
  // Normalise so a long intent vocabulary is not an advantage.
  return hits === 0 ? 0 : hits / words.length;
}

/**
 * Rank snippet intents against a plain-English query. `appCommands` are merged
 * by the caller so the palette can also drive the app now the toolbar is gone.
 */
export function suggest(
  text: string,
  opts: { hasSelection?: boolean; limit?: number } = {}
): Suggestion[] {
  const words = tokenize(text);
  const q: Query = {
    text,
    words,
    nums: (text.match(/\d+/g) ?? []).map(Number).slice(0, 2),
    hasSelection: opts.hasSelection ?? false,
  };

  const pool = q.hasSelection ? [...INTENTS, ...WRAPPERS] : INTENTS;
  const out: Suggestion[] = [];
  for (const intent of pool) {
    const score = scoreIntent(intent, words);
    if (score <= 0) continue;
    const built = intent.build(q);
    out.push({ id: intent.id, score: score + (intent.bias ?? 0), ...built });
  }

  out.sort((a, b) => b.score - a.score || a.title.localeCompare(b.title));
  return out.slice(0, opts.limit ?? 6);
}

/** Convert tab- or comma-separated lines into a tabular environment. */
export function selectionToTable(selection: string): string | null {
  const lines = selection.trim().split("\n").filter((l) => l.trim());
  if (lines.length === 0) return null;
  const split = (l: string) => (l.includes("\t") ? l.split("\t") : l.split(","));
  const grid = lines.map((l) => split(l).map((c) => c.trim()));
  const width = Math.max(...grid.map((r) => r.length));
  if (width < 2) return null;
  const body = grid
    .map((r) => "  " + [...r, ...Array(width - r.length).fill("")].join(" & ") + " \\\\")
    .join("\n");
  return `\\begin{tabular}{${"l".repeat(width)}}\n  \\hline\n${body}\n  \\hline\n\\end{tabular}`;
}
