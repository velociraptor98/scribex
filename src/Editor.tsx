import { useEffect, useRef } from "react";
import { EditorState } from "@codemirror/state";
import { EditorView, keymap, lineNumbers, highlightActiveLine } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { searchKeymap, highlightSelectionMatches } from "@codemirror/search";
import { bracketMatching, foldGutter, indentOnInput, syntaxHighlighting, defaultHighlightStyle } from "@codemirror/language";
import { closeBrackets, closeBracketsKeymap, completionKeymap } from "@codemirror/autocomplete";
import { latexLanguage, latexCompletion } from "./latex";

interface Props {
  initial: string;
  onChange: (value: string) => void;
  /** Set to scroll+focus a given 1-based line (used by log diagnostics). */
  gotoLine?: number;
}

export default function Editor({ initial, onChange, gotoLine }: Props) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView | null>(null);
  // Keep the latest callback without tearing down the editor on every render.
  const cb = useRef(onChange);
  cb.current = onChange;

  useEffect(() => {
    if (!host.current) return;

    const state = EditorState.create({
      doc: initial,
      extensions: [
        lineNumbers(),
        foldGutter(),
        history(),
        indentOnInput(),
        bracketMatching(),
        closeBrackets(),
        highlightActiveLine(),
        highlightSelectionMatches(),
        syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
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
        EditorView.updateListener.of((u) => {
          if (u.docChanged) cb.current(u.state.doc.toString());
        }),
        EditorView.theme({
          "&": { height: "100%", fontSize: "13px" },
          ".cm-scroller": { fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace" },
        }),
      ],
    });

    const v = new EditorView({ state, parent: host.current });
    view.current = v;
    return () => {
      v.destroy();
      view.current = null;
    };
    // Mount once; `initial` is the opened document, remounting is handled by key.
  }, []);

  useEffect(() => {
    const v = view.current;
    if (!v || !gotoLine) return;
    if (gotoLine < 1 || gotoLine > v.state.doc.lines) return;
    const pos = v.state.doc.line(gotoLine).from;
    v.dispatch({ selection: { anchor: pos }, scrollIntoView: true });
    v.focus();
  }, [gotoLine]);

  return <div ref={host} className="editor" />;
}
