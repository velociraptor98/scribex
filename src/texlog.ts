/**
 * TeX log → marginalia.
 *
 * TeX's own wording ("Undefined control sequence", "Missing $ inserted") tells
 * you what the parser felt, not what you did wrong. This module translates the
 * cases worth translating into a heading and a sentence, and — where the fix is
 * unambiguous — an edit the reader can accept. Anything it cannot translate is
 * passed through verbatim rather than guessed at.
 */

/** A single-line edit offered beside a mark. Applied by the caller. */
export interface Fix {
  label: string;
  /** 1-based line in the source. */
  line: number;
  find: string;
  replace: string;
}

export interface Diagnostic {
  severity: "error" | "warning";
  /** Short heading for the marginalia. */
  title: string;
  /** Explanatory sentence, when we have something better than the raw message. */
  detail?: string;
  /** TeX's own wording, always kept. */
  raw: string;
  line?: number;
  fixes?: Fix[];
}

/** What the parser can consult to make a suggestion. */
export interface Context {
  source?: string;
  /** Keys defined in the project's .bib files, for resolving citation typos. */
  bibKeys?: string[];
  /** File the .bib keys came from, named in the explanation. */
  bibName?: string;
}

const ERROR_RE = /^! (.+)$/;
const LINE_RE = /^l\.(\d+)/;
const WARNING_RE = /^(?:LaTeX|Package|Class)(?: (\S+))? Warning: (.+)$/;
const WARN_LINE_RE = /input line (\d+)/;

/* ── translation ─────────────────────────────────────────────────────────── */

const UNDEFINED_CITE = /Citation [`'"]([^'"`]+)['"`] on page \d+ undefined/;
const UNDEFINED_REF = /Reference [`'"]([^'"`]+)['"`] on page \d+ undefined/;
const ENV_MISMATCH = /\\begin\{([^}]+)\} on input line (\d+) ended by \\end\{([^}]+)\}/;
const FILE_NOT_FOUND = /File [`'"]([^'"`]+)['"`] not found/;
const OVERFULL = /^(Over|Under)full \\[hv]box/;

function levenshtein(a: string, b: string): number {
  const m = a.length, n = b.length;
  let prev = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) {
    const cur = [i];
    for (let j = 1; j <= n; j++) {
      cur[j] = Math.min(
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1)
      );
    }
    prev = cur;
  }
  return prev[n];
}

/** The closest candidate, if one is close enough to be worth proposing. */
function nearest(target: string, pool: string[]): string | null {
  let best: string | null = null;
  let bestD = Infinity;
  for (const c of pool) {
    const d = levenshtein(target.toLowerCase(), c.toLowerCase());
    if (d < bestD) { bestD = d; best = c; }
  }
  // A third of the key may differ before the guess stops being credible.
  return best !== null && bestD <= Math.max(2, Math.ceil(target.length / 3)) ? best : null;
}

/** Labels the document defines, for resolving \ref typos. */
function labelsIn(source: string): string[] {
  return [...source.matchAll(/\\label\s*\{([^}]+)\}/g)].map((m) => m[1]);
}

/** Locate `needle` in the source and return its 1-based line. */
function lineOf(source: string, needle: string, from = 1): number | undefined {
  const lines = source.split("\n");
  for (let i = from - 1; i < lines.length; i++) {
    if (lines[i].includes(needle)) return i + 1;
  }
  return undefined;
}

function translate(raw: string, line: number | undefined, ctx: Context): Diagnostic | null {
  const src = ctx.source ?? "";

  const cite = UNDEFINED_CITE.exec(raw);
  if (cite) {
    const key = cite[1];
    const guess = nearest(key, ctx.bibKeys ?? []);
    const at = line ?? lineOf(src, `{${key}}`) ?? lineOf(src, key);
    return {
      severity: "warning",
      title: `No such reference: ${key}`,
      detail: guess
        ? `Nothing in your bibliography matches. ScribeX found ${guess}${ctx.bibName ? ` in ${ctx.bibName}` : ""}.`
        : "Nothing in your bibliography matches this key.",
      raw,
      line: at,
      fixes:
        guess && at
          ? [{ label: `Use ${guess}`, line: at, find: key, replace: guess }]
          : undefined,
    };
  }

  const ref = UNDEFINED_REF.exec(raw);
  if (ref) {
    const key = ref[1];
    const guess = nearest(key, labelsIn(src));
    const at = line ?? lineOf(src, `{${key}}`);
    return {
      severity: "warning",
      title: `No such label: ${key}`,
      detail: guess
        ? `No \\label{${key}} is defined. The closest one is ${guess}.`
        : "No \\label with this key is defined, so the number cannot be resolved.",
      raw,
      line: at,
      fixes:
        guess && at
          ? [{ label: `Use ${guess}`, line: at, find: key, replace: guess }]
          : undefined,
    };
  }

  const env = ENV_MISMATCH.exec(raw);
  if (env) {
    const [, opened, atLine, closed] = env;
    const openLine = parseInt(atLine, 10);
    const closeLine = lineOf(src, `\\end{${closed}}`, openLine);
    return {
      severity: "error",
      title: `${opened} opened, ${closed} closed`,
      detail:
        "The environment names differ. Match them and the equation will number itself.",
      raw,
      line: openLine,
      fixes: closeLine
        ? [{
            label: `Fix both to ${opened}`,
            line: closeLine,
            find: `\\end{${closed}}`,
            replace: `\\end{${opened}}`,
          }]
        : undefined,
    };
  }

  const missing = FILE_NOT_FOUND.exec(raw);
  if (missing) {
    return {
      severity: "error",
      title: `Not in the cache: ${missing[1]}`,
      detail:
        "This resource is not on the machine. Fetch it once and it stays available offline.",
      raw,
      line,
    };
  }

  if (/^Undefined control sequence/.test(raw)) {
    return {
      severity: "error",
      title: "Unknown command",
      detail:
        "TeX does not recognise this command. Check the spelling, or load the package that defines it.",
      raw,
      line,
    };
  }

  if (/^Missing \$ inserted/.test(raw)) {
    return {
      severity: "error",
      title: "Maths outside maths mode",
      detail:
        "A symbol that only exists in maths appeared in prose. Wrap it in $…$.",
      raw,
      line,
    };
  }

  if (/^Missing [}{] inserted/.test(raw)) {
    return {
      severity: "error",
      title: "Unbalanced braces",
      detail: "A group was opened and never closed.",
      raw,
      line,
    };
  }

  if (/^Runaway argument/.test(raw)) {
    return {
      severity: "error",
      title: "Runaway argument",
      detail:
        "A command's argument was never closed, so TeX read to the end of the document looking for the brace.",
      raw,
      line,
    };
  }

  return null;
}

export function parseLog(log: string, ctx: Context = {}): Diagnostic[] {
  const lines = log.split("\n");
  const out: Diagnostic[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    const err = ERROR_RE.exec(line);
    if (err) {
      // TeX prints the offending source line a few lines below the message,
      // and often wraps the message itself onto the next line.
      let at: number | undefined;
      for (let j = i + 1; j < Math.min(i + 12, lines.length); j++) {
        const m = LINE_RE.exec(lines[j]);
        if (m) { at = parseInt(m[1], 10); break; }
      }
      let raw = err[1].trim();
      const cont = lines[i + 1]?.trim();
      if (cont && !/^[l!(]/.test(cont) && cont.length > 0) raw = `${raw} ${cont}`;
      raw = raw.replace(/^LaTeX Error:\s*/, "");

      out.push(translate(raw, at, ctx) ?? { severity: "error", title: raw, raw, line: at });
      continue;
    }

    const warn = WARNING_RE.exec(line);
    if (warn) {
      const cont = lines[i + 1]?.trim();
      const full =
        cont && !cont.startsWith("(") && cont.length > 0 && !/^!/.test(cont)
          ? `${warn[2]} ${cont}`
          : warn[2];
      const raw = full.trim();
      const lm = WARN_LINE_RE.exec(raw);
      const at = lm ? parseInt(lm[1], 10) : undefined;
      const t = translate(raw, at, ctx);
      out.push(
        t ?? { severity: "warning", title: raw, raw, line: at }
      );
    }
  }

  // One mark per problem: TeX repeats an undefined citation on every page.
  const seen = new Set<string>();
  return out.filter((d) => {
    const k = markKey(d);
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}

/** Stable identity for a mark, shared by de-duplication and "Ignore". */
export function markKey(d: Diagnostic): string {
  return `${d.severity}:${d.title}:${d.line ?? ""}`;
}

/* ── the press log ───────────────────────────────────────────────────────── */

export interface PressRow {
  stage: string;
  detail: string;
  /** Draws the detail in accent when something wants attention. */
  flagged?: boolean;
}

/**
 * What the run actually did.
 *
 * Tectonic drives its own passes internally and hands back one wall-clock
 * duration plus the final TeX log, so this reports per-stage *findings* rather
 * than per-stage timings — the timings simply are not measured. The total in
 * the header is real.
 */
export function pressLog(
  log: string,
  opts: { source?: string; name?: string; diags?: Diagnostic[] } = {}
): PressRow[] {
  const { source = "", name = "document.tex", diags = [] } = opts;
  const stem = name.replace(/\.tex$/i, "");
  const rows: PressRow[] = [];

  rows.push({ stage: "typeset", detail: `${name} → ${stem}.pdf` });

  const cited = new Set(
    [...source.matchAll(/\\cite\w*\s*(?:\[[^\]]*\])*\{([^}]*)\}/g)]
      .flatMap((m) => m[1].split(",").map((k) => k.trim()))
      .filter(Boolean)
  );
  if (cited.size > 0) {
    const unresolved = diags.filter((d) => d.title.startsWith("No such reference")).length;
    rows.push({
      stage: "bibliography",
      detail: unresolved
        ? `${unresolved} unresolved key${unresolved > 1 ? "s" : ""}`
        : `${cited.size} key${cited.size > 1 ? "s" : ""} resolved`,
      flagged: unresolved > 0,
    });
  }

  const labels = [...source.matchAll(/\\label\s*\{[^}]+\}/g)].length;
  if (labels > 0) {
    const dangling = diags.filter((d) => d.title.startsWith("No such label")).length;
    const rerun = /Label\(s\) may have changed/.test(log);
    rows.push({
      stage: "cross-refs",
      detail: rerun
        ? "labels moved — rebuilt to settle"
        : dangling
          ? `${dangling} unresolved`
          : `${labels} label${labels > 1 ? "s" : ""} resolved`,
      flagged: dangling > 0,
    });
  }

  const overfull = log.split("\n").filter((l) => OVERFULL.test(l)).length;
  if (overfull > 0) {
    rows.push({
      stage: "justification",
      detail: `${overfull} line${overfull > 1 ? "s" : ""} outside the measure`,
      flagged: true,
    });
  }

  return rows;
}
