import { StreamLanguage } from "@codemirror/language";
import { stex } from "@codemirror/legacy-modes/mode/stex";
import { autocompletion, CompletionContext } from "@codemirror/autocomplete";

export const latexLanguage = StreamLanguage.define(stex);

const COMMANDS = [
  "documentclass", "usepackage", "begin", "end", "section", "subsection",
  "subsubsection", "paragraph", "textbf", "textit", "texttt", "emph",
  "label", "ref", "eqref", "cite", "footnote", "item", "caption",
  "includegraphics", "frac", "sqrt", "sum", "int", "left", "right",
  "alpha", "beta", "gamma", "delta", "theta", "lambda", "mu", "pi", "sigma",
  "infty", "partial", "nabla", "cdot", "times", "leq", "geq", "neq", "approx",
];

const ENVIRONMENTS = [
  "document", "equation", "equation*", "align", "align*", "gather",
  "itemize", "enumerate", "description", "figure", "table", "tabular",
  "center", "quote", "verbatim", "abstract", "theorem", "proof", "matrix",
];

function completions(ctx: CompletionContext) {
  const env = ctx.matchBefore(/\\(begin|end)\{[\w*]*/);
  if (env) {
    const brace = env.text.indexOf("{");
    return {
      from: env.from + brace + 1,
      options: ENVIRONMENTS.map((label) => ({ label, type: "class" })),
    };
  }

  const cmd = ctx.matchBefore(/\\[a-zA-Z]*/);
  if (cmd && (cmd.from < cmd.to - 1 || ctx.explicit)) {
    return {
      from: cmd.from + 1,
      options: COMMANDS.map((label) => ({ label, type: "keyword" })),
    };
  }

  return null;
}

export const latexCompletion = autocompletion({ override: [completions] });

/** Section/subsection outline for the sidebar, derived by scanning the source. */
export interface OutlineEntry {
  level: number;
  title: string;
  line: number;
  /** As LaTeX would print it ("2.1"); empty for starred, unnumbered headings. */
  number: string;
}

// The title is read by brace matching below, so an empty `{}` or a nested
// `\emph{…}` inside it is taken whole.
const SECTION_RE = /^\s*\\(part|chapter|section|subsection|subsubsection)(\*?)\s*(?:\[[^\]]*\])?\s*\{/;
const LEVELS: Record<string, number> = {
  part: 0, chapter: 1, section: 2, subsection: 3, subsubsection: 4,
};
const ROMAN: [number, string][] = [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]];

function roman(n: number): string {
  let out = "";
  for (const [v, r] of ROMAN) for (; n >= v; n -= v) out += r;
  return out;
}

/** Everything up to the brace that closes the one before `from`, or the rest
 *  of the line if the title runs on. */
function braced(text: string, from: number): string {
  let depth = 1;
  for (let i = from; i < text.length; i++) {
    if (text[i] === "\\") i++;
    else if (text[i] === "{") depth++;
    else if (text[i] === "}" && --depth === 0) return text.slice(from, i);
  }
  return text.slice(from);
}

export function outline(source: string): OutlineEntry[] {
  const heads: { level: number; starred: boolean; title: string; line: number }[] = [];
  source.split("\n").forEach((text, i) => {
    const m = SECTION_RE.exec(text);
    if (m) {
      heads.push({
        level: LEVELS[m[1]],
        starred: m[2] === "*",
        title: braced(text, m[0].length).trim(),
        line: i + 1,
      });
    }
  });

  // Number like LaTeX: a heading resets the ones beneath it, starred headings
  // take no number, and parts count on their own without resetting chapters.
  // The dotted number starts at the shallowest level in use, so an article
  // reads 1, 1.1 rather than 0.1.
  const top = Math.max(1, Math.min(5, ...heads.filter((h) => h.level > 0).map((h) => h.level)));
  const counters = [0, 0, 0, 0, 0];
  return heads.map(({ level, starred, title, line }) => {
    if (starred) return { level, title, line, number: "" };
    counters[level]++;
    if (level > 0) counters.fill(0, level + 1);
    const number = level === 0 ? roman(counters[0]) : counters.slice(top, level + 1).join(".");
    return { level, title, line, number };
  });
}

/** The tally under the Contents panel. Counted from the source, not the log,
 *  so it stays honest while a build is failing. */
export interface DocStats {
  sections: number;
  equations: number;
  citations: number;
}

// Display maths only — inline $…$ is prose, not a numbered equation.
const EQUATION_ENVS = /\\begin\{(equation|align|gather|multline|eqnarray|displaymath)\*?\}/g;
const CITE_KEYS = /\\(?:cite|citep|citet|citeauthor|citeyear|parencite|textcite)\s*(?:\[[^\]]*\])*\{([^}]*)\}/g;

export function stats(source: string): DocStats {
  const keys = new Set<string>();
  for (const m of source.matchAll(CITE_KEYS)) {
    for (const k of m[1].split(",")) {
      const key = k.trim();
      if (key) keys.add(key);
    }
  }
  return {
    sections: outline(source).length,
    equations: [...source.matchAll(EQUATION_ENVS)].length,
    // Distinct works cited, not \cite calls — citing one paper twice is one
    // entry in the bibliography.
    citations: keys.size,
  };
}

const BIB_ENTRY = /@\w+\s*\{\s*([^,\s}]+)/g;

/** Bibliography keys defined in a .bib file, for resolving citation typos. */
export function bibKeys(bib: string): string[] {
  return [...bib.matchAll(BIB_ENTRY)].map((m) => m[1]);
}
