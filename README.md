# ScribeX

An offline LaTeX editor. Tauri shell, CodeMirror 6 editor, PDF.js viewer, and
[Tectonic](https://tectonic-typesetting.github.io/) as the typesetting engine.
No TeX Live installation or server is needed.

## Features

- Open, edit, save (⌘S), save as (⇧⌘S) and export to PDF (⌘E).
- Live rebuild 600 ms after you stop typing. A rebuild takes about 700 ms in a
  debug build once resources are cached.
- Section outline, and TeX log errors that jump to the offending line. Some
  errors come with a one-click fix.
- ⌘K palette: describe a snippet in plain English ("3 by 4 table") or run any
  app command. There is no toolbar.
- Export options for paper size and hyperlinked cross-references.
- Starter templates: article, letter, thesis, Beamer.

Preview never writes to your document. The engine typesets the editor buffer
from memory, so the file on disk changes only when you save. `\input` and
`\includegraphics` still resolve relative to the document's directory.

Not built yet: SyncTeX, a project file tree, a bundled resource cache.

## Running

Requires Rust, Node, and the C libraries Tectonic links against:

```sh
brew install harfbuzz freetype icu4c openssl@3 graphite2 libpng fontconfig
export PKG_CONFIG_PATH="/opt/homebrew/opt/icu4c@78/lib/pkgconfig:/opt/homebrew/opt/openssl@3/lib/pkgconfig:/opt/homebrew/lib/pkgconfig"

npm install
npm run tauri dev
```

The first Rust build compiles Tectonic's vendored C and takes several minutes.

**The first run needs the network once.** On a cold cache even `\maketitle`
fails offline, because its display-size font isn't cached. Click **Prime full
cache** when the banner appears. [docs/OFFLINE.md](docs/OFFLINE.md) has the
details.

## Layout

| Path | Role |
|---|---|
| `src-tauri/src/engine.rs` | Tectonic driver. Worker process only — see below |
| `src-tauri/src/worker.rs` | Runs each build in a child process, JSON over stdio |
| `src-tauri/src/lib.rs` | Tauri commands: compile, save, export, cache warmup, offline toggle |
| `src/App.tsx` | App state, builds, file handling, shortcuts |
| `src/Editor.tsx` | CodeMirror 6 setup, LaTeX mode, completion |
| `src/PdfView.tsx` | PDF.js renderer; keeps scroll position across rebuilds |
| `src/texlog.ts` | Parses the TeX log into diagnostics and the build log |
| `src/latex.ts` | LaTeX mode, completions, outline, document counts |
| `src/Welcome.tsx` | Welcome screen: recent documents and templates |
| `src/Palette.tsx` | ⌘K palette UI |
| `src/commands.ts` | Plain-English → LaTeX snippet matcher (local keyword scoring) |
| `src/Marks.tsx` | Diagnostics panel and build log |
| `src/ExportSheet.tsx` | Export dialog |
| `src/exporting.ts` | Source rewrites for export options |
| `src/theme.css` | Design tokens |

## Before changing anything

1. **Typesetting must stay in the worker process.** A failed run leaves
   Tectonic's C globals dirty, and the next run in the same process aborts
   through a panic that can't unwind. Run in the GUI process, that takes down
   the whole app.
2. **`tectonic` is pinned to a git commit, not crates.io.** The published 0.15.0
   doesn't compile against its own published sibling crates.

Both are explained in [docs/OFFLINE.md](docs/OFFLINE.md).
