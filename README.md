# ScribeX

An offline LaTeX reader and editor. Tauri shell, CodeMirror 6 editor, PDF.js
viewer, and [Tectonic](https://tectonic-typesetting.github.io/) as the
typesetting engine — no TeX Live installation, no server.

## Status

Working end to end: edit, live rebuild on a 600 ms debounce, PDF preview,
section outline, and TeX log diagnostics that jump to the offending line.
Typical rebuild is ~700 ms (debug build) once resources are cached.

Not yet built: SyncTeX, multi-file projects, save-as, a shipped resource bundle.

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
| `src-tauri/src/lib.rs` | Tauri commands, offline toggle |
| `src/Editor.tsx` | CodeMirror 6, LaTeX mode, completion |
| `src/PdfView.tsx` | PDF.js canvas renderer, scroll-preserving |
| `src/texlog.ts` | TeX log → diagnostics |
| `src/latex.ts` | LaTeX mode, completions, outline |

## Two things worth knowing before changing anything

1. **Typesetting must stay in the worker process.** A failed run leaves
   Tectonic's C globals dirty, and the next in-process run aborts via a panic
   that cannot unwind. This crashes the whole app, not just the build.
2. **`tectonic` is pinned to git, not crates.io.** The published 0.15.0 does not
   compile against its own published sibling crates.

Both are explained in [docs/OFFLINE.md](docs/OFFLINE.md).
