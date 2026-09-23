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
}

const SECTION_RE = /^\s*\\(part|chapter|section|subsection|subsubsection)\*?\{(.+?)\}/;
const LEVELS: Record<string, number> = {
  part: 0, chapter: 1, section: 2, subsection: 3, subsubsection: 4,
};

export function outline(source: string): OutlineEntry[] {
  const out: OutlineEntry[] = [];
  source.split("\n").forEach((text, i) => {
    const m = SECTION_RE.exec(text);
    if (m) out.push({ level: LEVELS[m[1]], title: m[2], line: i + 1 });
  });
  return out;
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
