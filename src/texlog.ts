/**
 * Minimal TeX log parser: enough to surface errors and warnings with line
 * numbers. TeX logs are notoriously irregular — if this proves too thin,
 * swap in Overleaf's `latex-log-parser`, which handles far more edge cases.
 */

export interface Diagnostic {
  severity: "error" | "warning";
  message: string;
  line?: number;
  file?: string;
}

// "! LaTeX Error: File `tikz.sty' not found." / "! Undefined control sequence."
const ERROR_RE = /^! (.+)$/;
// "l.42 \begin"  → the line TeX choked on
const LINE_RE = /^l\.(\d+)/;
// "LaTeX Warning: Reference `fig:x' on page 1 undefined on input line 12."
const WARNING_RE = /^(?:LaTeX|Package|Class)(?: (\S+))? Warning: (.+)$/;
const WARN_LINE_RE = /input line (\d+)/;

export function parseLog(log: string): Diagnostic[] {
  const lines = log.split("\n");
  const out: Diagnostic[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    const err = ERROR_RE.exec(line);
    if (err) {
      // TeX prints the offending source line a few lines below the message.
      let at: number | undefined;
      for (let j = i + 1; j < Math.min(i + 12, lines.length); j++) {
        const m = LINE_RE.exec(lines[j]);
        if (m) {
          at = parseInt(m[1], 10);
          break;
        }
      }
      out.push({ severity: "error", message: err[1].trim(), line: at });
      continue;
    }

    const warn = WARNING_RE.exec(line);
    if (warn) {
      // Warnings often wrap onto the following line.
      const cont = lines[i + 1]?.trim();
      const full = cont && !cont.startsWith("(") && cont.length > 0 && !/^!/.test(cont)
        ? `${warn[2]} ${cont}`
        : warn[2];
      const lm = WARN_LINE_RE.exec(full);
      out.push({
        severity: "warning",
        message: full.trim(),
        line: lm ? parseInt(lm[1], 10) : undefined,
        file: warn[1],
      });
    }
  }

  return out;
}
