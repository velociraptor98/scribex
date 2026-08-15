import { forwardRef, useEffect, useImperativeHandle, useRef } from "react";
import { EditorState } from "@codemirror/state";
import { EditorView, keymap, lineNumbers, highlightActiveLine } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { searchKeymap, highlightSelectionMatches } from "@codemirror/search";
import { HighlightStyle, bracketMatching, foldGutter, indentOnInput, syntaxHighlighting } from "@codemirror/language";
import { closeBrackets, closeBracketsKeymap, completionKeymap } from "@codemirror/autocomplete";
import { tags as t } from "@lezer/highlight";
import { latexLanguage, latexCompletion } from "./latex";
import { CARET } from "./commands";

/** Imperative handle used by the palette and by the marginalia's quick fixes. */
export interface EditorHandle {
  /** Insert at the caret, replacing any selection. A CARET marker in `text`
   *  sets where the caret lands; otherwise it lands after the insertion. */
  insert: (text: string) => void;
  /** Replace the first occurrence of `find` on a 1-based line. */
  replaceOnLine: (line: number, find: string, replace: string) => void;
  goto: (line: number) => void;
  selection: () => string;
  focus: () => void;
}

interface Props {
  /** Document text. Only read at mount and when `docKey` changes — the editor
   *  owns the text while the user is typing, so this is not a controlled value. */
  doc: string;
  /** Change this to load a different document (e.g. on File → Open). */
  docKey: string | number;
  onChange: (value: string) => void;
  /** Fired as the selection changes, so the palette can offer selection-aware
   *  actions without reading the view itself. */
  onSelection?: (text: string) => void;
}

/* The mockup's source pane: gilt commands on near-black, set on a 28px rhythm
   so the lines align with the typeset page beside them. */
const latexHighlight = HighlightStyle.define([
  { tag: t.tagName, color: "var(--accent)" },
  { tag: [t.atom, t.keyword], color: "var(--accent-400)" },
  { tag: [t.string, t.number], color: "var(--accent-400)" },
  { tag: t.bracket, color: "var(--text-55)" },
  { tag: t.comment, color: "var(--text-38)", fontStyle: "italic" },
  { tag: t.variableName, color: "var(--text)" },
  { tag: t.invalid, color: "var(--mark)" },
]);

const theme = EditorView.theme(
  {
    "&": { height: "100%", backgroundColor: "transparent", color: "var(--text)" },
    ".cm-scroller": {
      fontFamily: "var(--font-mono)",
      fontSize: "13px",
      lineHeight: "28px",
      padding: "34px 30px 40px 0",
    },
    ".cm-content": { caretColor: "var(--accent)" },
    ".cm-gutters": {
      backgroundColor: "transparent",
      border: "none",
      color: "var(--text-24)",
      fontVariantNumeric: "tabular-nums",
      paddingRight: "14px",
    },
    ".cm-lineNumbers .cm-gutterElement": { padding: "0 0 0 12px", minWidth: "34px" },
    ".cm-foldGutter .cm-gutterElement": { color: "var(--text-24)" },
    ".cm-activeLine": { backgroundColor: "var(--accent-wash-soft)" },
    ".cm-activeLineGutter": { backgroundColor: "transparent", color: "var(--text-55)" },
    "&.cm-focused .cm-cursor": { borderLeftColor: "var(--accent)", borderLeftWidth: "2px" },
    "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection": {
      backgroundColor: "rgba(194,141,65,0.22)",
    },
    ".cm-matchingBracket, &.cm-focused .cm-matchingBracket": {
      backgroundColor: "rgba(194,141,65,0.18)",
      color: "inherit",
      outline: "none",
    },
    ".cm-selectionMatch": { backgroundColor: "rgba(236,231,223,0.08)" },
    ".cm-tooltip": {
      backgroundColor: "var(--ink-panel)",
      border: "1px solid var(--rule-strong)",
      borderRadius: "var(--radius-md)",
      color: "var(--text)",
    },
    ".cm-tooltip-autocomplete ul li[aria-selected]": {
      backgroundColor: "var(--accent-wash)",
      color: "var(--accent-300)",
    },
    ".cm-panels": { backgroundColor: "var(--ink-raised)", color: "var(--text)" },
    ".cm-searchMatch": { backgroundColor: "rgba(194,141,65,0.24)" },
  },
  { dark: true }
);

const Editor = forwardRef<EditorHandle, Props>(function Editor(
  { doc, docKey, onChange, onSelection },
  ref
) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView | null>(null);
  // Keep the latest callbacks and text without tearing down the editor on
  // every render.
  const cb = useRef(onChange);
  cb.current = onChange;
  const sel = useRef(onSelection);
  sel.current = onSelection;
  const latest = useRef(doc);
  latest.current = doc;

  function makeState(text: string) {
    return EditorState.create({
      doc: text,
      extensions: [
        lineNumbers(),
        foldGutter(),
        history(),
        indentOnInput(),
        bracketMatching(),
        closeBrackets(),
        highlightActiveLine(),
        highlightSelectionMatches(),
        syntaxHighlighting(latexHighlight, { fallback: true }),
        latexLanguage,
        latexCompletion,
        keymap.of([
          ...closeBracketsKeymap,
          ...defaultKeymap,
          ...historyKeymap,
          ...searchKeymap,
          ...completionKeymap,
          indentWithTab,
        ]),
        EditorView.lineWrapping,
        theme,
        EditorView.updateListener.of((u) => {
          if (u.docChanged) cb.current(u.state.doc.toString());
          if (u.selectionSet || u.docChanged) {
            const r = u.state.selection.main;
            sel.current?.(r.empty ? "" : u.state.sliceDoc(r.from, r.to));
          }
        }),
      ],
    });
  }

  useEffect(() => {
    if (!host.current) return;
    const v = new EditorView({ state: makeState(latest.current), parent: host.current });
    view.current = v;
    return () => {
      v.destroy();
      view.current = null;
    };
  }, []);

  // Load a different document. Replacing the whole state (rather than
  // dispatching a change) also clears undo history, so you cannot undo your way
  // out of the newly opened file and back into the previous one.
  const loaded = useRef(docKey);
  useEffect(() => {
    const v = view.current;
    if (!v || loaded.current === docKey) return;
    loaded.current = docKey;
    v.setState(makeState(latest.current));
  }, [docKey]);

  useImperativeHandle(ref, (): EditorHandle => ({
    insert(text) {
      const v = view.current;
      if (!v) return;
      const at = text.indexOf(CARET);
      const clean = text.replace(CARET, "");
      const { from, to } = v.state.selection.main;
      v.dispatch({
        changes: { from, to, insert: clean },
        selection: { anchor: from + (at < 0 ? clean.length : at) },
        scrollIntoView: true,
      });
      v.focus();
    },

    replaceOnLine(line, find, replace) {
      const v = view.current;
      if (!v || line < 1 || line > v.state.doc.lines) return;
      const l = v.state.doc.line(line);
      const at = l.text.indexOf(find);
      if (at < 0) return;
      v.dispatch({
        changes: { from: l.from + at, to: l.from + at + find.length, insert: replace },
        selection: { anchor: l.from + at + replace.length },
        scrollIntoView: true,
      });
    },

    goto(line) {
      const v = view.current;
      if (!v || line < 1 || line > v.state.doc.lines) return;
      v.dispatch({ selection: { anchor: v.state.doc.line(line).from }, scrollIntoView: true });
      v.focus();
    },

    selection() {
      const v = view.current;
      if (!v) return "";
      const r = v.state.selection.main;
      return r.empty ? "" : v.state.sliceDoc(r.from, r.to);
    },

    focus() { view.current?.focus(); },
  }), []);

  return <div ref={host} className="editor" />;
});

export default Editor;
