import { useEffect, useRef } from "react";
import { EditorState } from "@codemirror/state";
import { EditorView, keymap, lineNumbers, highlightActiveLine } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { searchKeymap, highlightSelectionMatches } from "@codemirror/search";
import { bracketMatching, foldGutter, indentOnInput, syntaxHighlighting, defaultHighlightStyle } from "@codemirror/language";
import { closeBrackets, closeBracketsKeymap, completionKeymap } from "@codemirror/autocomplete";
import { latexLanguage, latexCompletion } from "./latex";

interface Props {
  /** Document text. Only read at mount and when `docKey` changes — the editor
   *  owns the text while the user is typing, so this is not a controlled value. */
  doc: string;
  /** Change this to load a different document (e.g. on File → Open). */
  docKey: string | number;
  onChange: (value: string) => void;
  /** Set to scroll+focus a given 1-based line (used by log diagnostics). */
  gotoLine?: number;
}

export default function Editor({ doc, docKey, onChange, gotoLine }: Props) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView | null>(null);
  // Keep the latest callback and text without tearing down the editor on
  // every render.
  const cb = useRef(onChange);
  cb.current = onChange;
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
