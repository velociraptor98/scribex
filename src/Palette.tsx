/** 1c — the ⌘K palette: plain English in, LaTeX out.
 *
 *  It is also where the app's own commands live, since the redesign retires the
 *  toolbar. Snippet suggestions rank above commands when the query looks like a
 *  request for LaTeX, and below them when it names a command. */

import { useEffect, useMemo, useRef, useState } from "react";
import { Suggestion, suggest, tokenize } from "./commands";

export interface AppCommand {
  id: string;
  title: string;
  hint?: string;
  /** Words the query is scored against, beyond those in the title. */
  words?: string[];
  run: () => void;
  disabled?: boolean;
}

interface Props {
  commands: AppCommand[];
  hasSelection: boolean;
  onInsert: (text: string) => void;
  onClose: () => void;
}

type Row = Suggestion & { command?: AppCommand };

export default function Palette({ commands, hasSelection, onInsert, onClose }: Props) {
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  const list = useRef<HTMLDivElement>(null);

  useEffect(() => { input.current?.focus(); }, []);

  const rows = useMemo<Row[]>(() => {
    const q = query.trim();
    const cmds = commands.filter((c) => !c.disabled);

    // No query: the palette is a menu. Show the commands, in their given order.
    if (!q) {
      return cmds.map((c) => ({ id: c.id, title: c.title, hint: c.hint, score: 1, command: c }));
    }

    // Same tokenizer as the snippet matcher, so filler words ("a", "put",
    // "here") cannot drag in every command that happens to contain the letter.
    const words = tokenize(q);
    const scored = cmds
      .map((c) => {
        const hay = tokenize(`${c.title} ${(c.words ?? []).join(" ")}`);
        let hits = 0;
        // Match whole words or their prefixes, never substrings — otherwise
        // "as" finds "Save as…" by way of the middle of a word.
        for (const w of words) if (hay.some((h) => h.startsWith(w) || w.startsWith(h))) hits++;
        return { c, score: words.length ? hits / words.length : 0 };
      })
      .filter((x) => x.score > 0)
      .sort((a, b) => b.score - a.score)
      .map(({ c, score }) => ({
        id: c.id, title: c.title, hint: c.hint,
        // Commands and snippets share a scale; an exact command match should
        // outrank a loose snippet match, but never a precise one.
        score: score * 0.95,
        command: c,
      }));

    const snippets = suggest(q, { hasSelection, limit: 6 });
    return [...snippets, ...scored].sort((a, b) => b.score - a.score).slice(0, 7);
  }, [query, commands, hasSelection]);

  useEffect(() => { setActive(0); }, [query]);

  // Keep the highlighted row in view when arrowing past the fold.
  useEffect(() => {
    list.current?.querySelector<HTMLElement>('[data-active="true"]')
      ?.scrollIntoView({ block: "nearest" });
  }, [active]);

  function choose(row: Row | undefined) {
    if (!row) return;
    if (row.command) row.command.run();
    else if (row.text) onInsert(row.text);
    onClose();
  }

  function onKey(e: React.KeyboardEvent) {
    if (e.key === "Escape") { e.preventDefault(); onClose(); }
    else if (e.key === "ArrowDown") { e.preventDefault(); setActive((i) => Math.min(rows.length - 1, i + 1)); }
    else if (e.key === "ArrowUp") { e.preventDefault(); setActive((i) => Math.max(0, i - 1)); }
    else if (e.key === "Enter") { e.preventDefault(); choose(rows[active]); }
  }

  const best = rows[0];
  const rest = rows.slice(1);

  return (
    <div className="scrim" onMouseDown={onClose}>
      <div className="palette" onMouseDown={(e) => e.stopPropagation()} role="dialog" aria-label="Command palette">
        <div className="palette-field">
          <span className="palette-key">⌘K</span>
          <input
            ref={input}
            className="palette-input"
            value={query}
            placeholder="put a 3 by 4 table here"
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={onKey}
            spellCheck={false}
          />
          <span className="palette-mode">{query.trim() ? "Plain English" : "Commands"}</span>
        </div>

        <div className="palette-rows" ref={list}>
          {rows.length === 0 && (
            <div className="palette-none">
              Nothing matches. Try naming what you want — “a bulleted list”,
              “aligned equations”, “a figure with a caption”.
            </div>
          )}

          {best && (
            <>
              {query.trim() && <div className="palette-group">Best match</div>}
              <Item row={best} active={active === 0} onPick={() => choose(best)} onHover={() => setActive(0)} best />
            </>
          )}

          {rest.length > 0 && (
            <>
              {query.trim() && <div className="palette-group palette-group-also">Also</div>}
              {rest.map((row, i) => (
                <Item
                  key={row.id}
                  row={row}
                  active={active === i + 1}
                  onPick={() => choose(row)}
                  onHover={() => setActive(i + 1)}
                />
              ))}
            </>
          )}
        </div>

        <div className="palette-foot">
          <span>↑↓ to choose · ↵ to {best?.command ? "run" : "insert"}</span>
          <span>Nothing leaves this machine</span>
        </div>
      </div>
    </div>
  );
}

function Item({
  row, active, best, onPick, onHover,
}: {
  row: Row; active: boolean; best?: boolean;
  onPick: () => void; onHover: () => void;
}) {
  return (
    <button
      className={`palette-item${best ? " is-best" : ""}`}
      data-active={active}
      onClick={onPick}
      onMouseMove={onHover}
    >
      <span className="palette-item-main">
        <span className="palette-item-title">{row.title}</span>
        {row.preview && <span className="palette-item-preview">{row.preview}</span>}
      </span>
      {best ? <span className="palette-enter">↵</span> : row.hint && <span className="palette-hint">{row.hint}</span>}
    </button>
  );
}
