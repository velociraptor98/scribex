import { StreamLanguage } from "@codemirror/language";
import { stex } from "@codemirror/legacy-modes/mode/stex";
import { autocompletion, CompletionContext } from "@codemirror/autocomplete";

export const latexLanguage = StreamLanguage.define(stex);

// A deliberately small starter set. The real version should harvest \newcommand
// and \label from the open project, plus package names from the Tectonic cache.
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
  // \begin{...} / \end{...} → environment names
  const env = ctx.matchBefore(/\\(begin|end)\{[\w*]*/);
  if (env) {
    const brace = env.text.indexOf("{");
    return {
      from: env.from + brace + 1,
      options: ENVIRONMENTS.map((label) => ({ label, type: "class" })),
    };
  }

  // \... → command names
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
