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
export PKG_CONFIG_PATH="$(brew --prefix icu4c)/lib/pkgconfig:$(brew --prefix openssl@3)/lib/pkgconfig:$(brew --prefix)/lib/pkgconfig"

npm install
npm run tauri dev
```

`brew --prefix` resolves the paths, so this works on Apple Silicon
(`/opt/homebrew`), Intel (`/usr/local`) and custom Homebrew locations. ICU and
OpenSSL are keg-only, so pkg-config can't find them without these entries.
Add the line to your shell profile to keep it across sessions.

The first Rust build compiles Tectonic's vendored C and takes several minutes.

**The first run needs the network once.** On a cold cache even `\maketitle`
fails offline, because its display-size font isn't cached. Click **Prime full
cache** when the banner appears. [docs/OFFLINE.md](docs/OFFLINE.md) has the
details.

## Building the macOS app

With `PKG_CONFIG_PATH` set as above:

```sh
npm run tauri build       # ad-hoc signed, for this machine
npm run build:release     # Developer ID signed; set APPLE_SIGNING_IDENTITY first
```

Output lands in `src-tauri/target/release/bundle/` (`macos/ScribeX.app`, `dmg/`).
The DMG step uses AppleScript to lay out the Finder window, which needs your
terminal to have Automation permission for Finder. Without it the build fails
with `error running bundle_dmg.sh` (the verbose log shows `Not authorised to
send Apple events to Finder (-1743)`). Either allow it under System Settings →
Privacy & Security → Automation, or build with `CI=true npm run tauri build`,
which skips the layout step and uses Finder's default window.

Tectonic links ICU, FreeType, Graphite2 and libpng from Homebrew. The build
ships them inside the app, and nothing in it assumes a Homebrew location or a
library version:

- `npm run tauri …` first runs `src-tauri/scripts/stage-dylibs.sh`. It asks
  pkg-config where the libraries are, follows their dependencies, and copies
  them into `src-tauri/frameworks/` with `@rpath` install names. It then writes
  `src-tauri/tauri.macos.conf.json` (gitignored), which Tauri merges into
  `tauri.conf.json` on macOS. That file lists the libraries and sets
  `minimumSystemVersion` to the highest macOS version they were built for.
- `src-tauri/scripts/relink-binary.sh`, run as `beforeBundleCommand`, points
  the binary at the bundled copies. It fails the build if the binary still
  links a non-system library that wasn't bundled.

Run Tauri through `npm run tauri`, not `npx tauri` or the global CLI, so the
staging step runs. The minimum macOS version follows the machine that builds:
current Homebrew targets its own macOS release, which is macOS 26 here. The
ad-hoc build turns off the hardened
runtime: its library validation rejects ad-hoc signed libraries. The release
config turns it back on, which notarization requires.

Third-party licenses ship in `Contents/Resources/licenses/`; see
[THIRD-PARTY-NOTICES.md](src-tauri/licenses/THIRD-PARTY-NOTICES.md). Portions
of this software are copyright © 2026 The FreeType Project
(https://freetype.org). All rights reserved.

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
