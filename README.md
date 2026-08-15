# ScribeX

An offline LaTeX reader and editor. Tauri shell, CodeMirror 6 editor, PDF.js
viewer, and [Tectonic](https://tectonic-typesetting.github.io/) as the
typesetting engine — no TeX Live installation, no server.

## Status

Working end to end: open, edit, save (⌘S) and save-as (⇧⌘S), export (⌘E),
live rebuild on a 600 ms debounce, PDF preview, section outline, and TeX log
diagnostics that jump to the offending line. Typical rebuild is ~700 ms (debug
build) once resources are cached.

The interface is the dark editorial variant of *Classical* — a title page
rather than a dashboard, a facing-page spread rather than a toolbar. Five
screens:

| Screen | What it is |
|---|---|
| Welcome | Recent documents, and four starter plates |
| Editor | Contents in the margin, source verso, proof recto |
| Palette (⌘K) | Plain English in, LaTeX out — and every app command |
| Marks | TeX errors rewritten as a proof-reader's slips, with one-click fixes |
| Imprint sheet | Export, with paper size and hyperlinked cross-references |

There is no toolbar; ⌘K reaches everything. Type is Cormorant Garamond and
Lora, bundled as woff2 under `public/fonts/` — the app never fetches a
webfont, for the same reason it never fetches anything else.

**Preview never writes to your document.** The engine typesets the editor
buffer from memory, so the file on disk changes only when you save. Multi-file
projects still resolve — `\input` and `\includegraphics` are looked up relative
to the document's real directory.

Not yet built: SyncTeX, a project/file tree, a shipped resource bundle.

## Running

Requires Rust, Node, and the C libraries Tectonic links against:

```sh
brew install harfbuzz freetype icu4c openssl@3 graphite2 libpng fontconfig
export PKG_CONFIG_PATH="/opt/homebrew/opt/icu4c@78/lib/pkgconfig:/opt/homebrew/opt/openssl@3/lib/pkgconfig:/opt/homebrew/lib/pkgconfig"

npm install
npm run tauri dev
```

The first Rust build compiles Tectonic's vendored C and takes several minutes.

**First run needs the network once.** With the cache cold, even `\maketitle`
fails offline because its display-size font is not present. Click **Prime full
cache** when the banner appears. [docs/OFFLINE.md](docs/OFFLINE.md) explains
why, and covers the two non-obvious constraints this design is built around.

## Layout

| Path | Role |
|---|---|
| `src-tauri/src/engine.rs` | Tectonic driver. **Worker process only** — see docs |
| `src-tauri/src/worker.rs` | Crash isolation: re-exec + JSON over stdio |
| `src-tauri/src/lib.rs` | Tauri commands: compile, save, export, offline toggle |
| `src/Editor.tsx` | CodeMirror 6, LaTeX mode, completion |
| `src/PdfView.tsx` | PDF.js canvas renderer, scroll-preserving |
| `src/texlog.ts` | TeX log → marks and the press log |
| `src/latex.ts` | LaTeX mode, completions, outline, document tally |
| `src/theme.css` | Design tokens. The look is retuned here |
| `src/Welcome.tsx` | Title page: recent documents and plates |
| `src/Palette.tsx` | ⌘K — snippet suggestions merged with app commands |
| `src/commands.ts` | The plain-English → LaTeX matcher (local, no model) |
| `src/Marks.tsx` | Marginalia and the press log |
| `src/ExportSheet.tsx` | The imprint sheet |
| `src/exporting.ts` | Rewrites that make the export options real |

## Two things worth knowing before changing anything

1. **Typesetting must stay in the worker process.** A failed run leaves
   Tectonic's C globals dirty, and the next in-process run aborts via a panic
   that cannot unwind. This crashes the whole app, not just the build.
2. **`tectonic` is pinned to git, not crates.io.** The published 0.15.0 does not
   compile against its own published sibling crates.

Both are explained in [docs/OFFLINE.md](docs/OFFLINE.md).
