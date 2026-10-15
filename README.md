# ScribeX

An offline LaTeX editor for macOS: a native Swift app (SwiftUI, STTextView,
PDFKit) over [Tectonic](https://tectonic-typesetting.github.io/), which is
driven from Rust. No TeX Live installation or server is needed.

## Features

- A standard Mac document app: one window per .tex file, with Save, Save As,
  Revert, Rename, Auto Save, Versions and Open Recent from macOS itself, and
  export to PDF (⌘E).
- A welcome window with the system's recent documents and starter templates.
- Live rebuild 600 ms after you stop typing. A rebuild takes about 700 ms once
  resources are cached.
- Section outline, and TeX log errors that jump to the offending line. Some
  errors come with a one-click fix.
- ⌘K palette: describe a snippet in plain English ("3 by 4 table") or run any
  app command. Every command is also in the menu bar.
- Export options for paper size and hyperlinked cross-references.
- Starter templates: article, letter, thesis, Beamer.

Preview never writes to your document. The engine typesets the editor buffer
from memory, so the file on disk changes only when you save. `\input` and
`\includegraphics` still resolve relative to the document's directory.

Not built yet: SyncTeX, a project file tree, a bundled resource cache.

## Building

Requires Xcode 26 or later, Rust, and the C libraries Tectonic links against:

```sh
brew install harfbuzz freetype icu4c openssl@3 graphite2 libpng fontconfig
```

Then open `macos/ScribeX.xcodeproj` and run the ScribeX scheme, or from a
terminal:

```sh
xcodebuild -project macos/ScribeX.xcodeproj -scheme ScribeX \
  -configuration Debug -derivedDataPath macos/build/DerivedData build
open macos/build/DerivedData/Build/Products/Debug/ScribeX.app
```

The first build compiles Tectonic's vendored C and takes several minutes.

**The first run needs the network once.** On a cold cache even `\maketitle`
fails offline, because its display-size font isn't cached. Click **Download
now** when the app offers it. [docs/OFFLINE.md](docs/OFFLINE.md) has the
details.

### What the build does with the engine

The "Embed Typesetting Engine" build phase (`macos/scripts/embed-engine.sh`):

1. Builds the `scribex-typeset` worker with cargo and copies it into
   `Contents/MacOS`, beside the app's own executable.
2. Copies ICU, FreeType, Graphite2 and libpng, which Tectonic links from
   Homebrew, into `Contents/Frameworks` with `@rpath` install names
   (`macos/scripts/stage-dylibs.sh`), and points the worker at those copies. It
   fails the build if the worker still links a library that wasn't bundled.
3. Copies the third-party licences from `macos/licenses/` into
   `Contents/Resources/licenses`.
4. Signs the worker and libraries with the app's identity.

It finds Homebrew and sets `PKG_CONFIG_PATH` itself, and runs cargo in a clean
environment so Xcode's build settings don't invalidate cargo's cache. Nothing
in it assumes a Homebrew location or a library version. The minimum macOS
version follows the machine that builds: current Homebrew targets its own
macOS release, which is macOS 26 here.

Debug builds are ad-hoc signed and run on this machine only. Release builds
turn on the hardened runtime, which notarization needs; with ad-hoc signing
the worker is left without it, because its library validation rejects ad-hoc
signed libraries.

The app is built for Apple Silicon only: the worker and the Homebrew libraries
are built for the machine that builds them, so the app target is pinned to
arm64 to match.

## Distributing

`macos/scripts/make-dmg.sh` builds a Release app and packages it as
`macos/build/dist/ScribeX-<version>.dmg`.

### Without an Apple Developer account

Run it with no settings. The app is signed ad hoc, which is enough to share:
the first time someone opens it, macOS blocks it ("Apple could not verify
'ScribeX' is free of malware"). They allow it once under System Settings →
Privacy & Security → Open Anyway, and it opens normally from then on. On
macOS 15 and later right-click → Open no longer offers this. Alternatively:

```sh
xattr -dr com.apple.quarantine /Applications/ScribeX.app
```

### With an Apple Developer account

Signing with a Developer ID and notarizing removes that step. It needs a paid
Apple Developer account, set up once:

1. Create a **Developer ID Application** certificate: Xcode → Settings →
   Accounts → Manage Certificates → + → Developer ID Application.
   `security find-identity -v -p codesigning` then lists its full name.
2. Store notarization credentials in the keychain, using an app-specific
   password from account.apple.com:

   ```sh
   xcrun notarytool store-credentials scribex --apple-id you@example.com --team-id TEAMID
   ```

Then:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=scribex macos/scripts/make-dmg.sh
```

This signs the app, its worker and libraries with the Developer ID and a
secure timestamp, notarizes and staples the app, then packages, signs,
notarizes and staples the DMG. Stapling the app as well means it passes
Gatekeeper after being copied out of the DMG, even offline. Each notarization
round usually takes a few minutes.

Raise the version (`MARKETING_VERSION`) and the build number
(`CURRENT_PROJECT_VERSION`) in the Xcode target before each release, and check
the STTextView licence under Licences below.

## Testing

```sh
cargo test -p scribex-engine               # the engine, including the worker binary
cargo build -p scribex-engine              # the worker the Swift integration tests run
cd macos/ScribeXKit && swift test          # everything but the app shell
```

Tests that typeset need a primed Tectonic cache, since they build offline;
without one they report that they were skipped.

Debug builds can drive themselves and render their window to PNGs, which needs
no Screen Recording permission; see `DebugScript.swift`.

## Layout

| Path | Role |
|---|---|
| `engine/src/engine.rs` | Tectonic driver. Worker process only — see below |
| `engine/src/worker.rs` | The worker protocol: one JSON request in, one response out |
| `engine/src/bin/scribex-typeset.rs` | The worker binary the app launches for each build |
| `macos/ScribeX/` | The app target: entry point and icon |
| `macos/ScribeXKit/Sources/ScribeXCore/Typesetter.swift` | Runs builds in the worker, one at a time per build folder, with time limits; first-run download |
| `macos/ScribeXKit/Sources/ScribeXCore/DocumentFiles.swift` | Export, and the source written alongside an export |
| `macos/ScribeXKit/Sources/ScribeXCore/Latex/Issues.swift` | Turns the TeX log into issues, with plain-English titles and fixes |
| `macos/ScribeXKit/Sources/ScribeXCore/Latex/Outline.swift` | Headings with LaTeX's numbering, document counts, the title |
| `macos/ScribeXKit/Sources/ScribeXCore/Latex/Bibliography.swift` | Cited keys and the entries in .bib files |
| `macos/ScribeXKit/Sources/ScribeXCore/Latex/Completions.swift` | The command and environment names the editor completes |
| `macos/ScribeXKit/Sources/ScribeXCore/Latex/Highlighting.swift` | Tokens for syntax colouring, line by line |
| `macos/ScribeXKit/Sources/ScribeXCore/Content/Snippets.swift` | Plain-English → LaTeX snippet matcher |
| `macos/ScribeXKit/Sources/ScribeXCore/Content/Templates.swift` | Starter templates; their LaTeX is in `Resources/Templates` |
| `macos/ScribeXKit/Sources/ScribeXUI/Editor/TexDocument.swift` | The .tex document type; the document system does the file handling |
| `macos/ScribeXKit/Sources/ScribeXUI/App/Engine.swift` | Shared by all windows: the typesetter and its download cache |
| `macos/ScribeXKit/Sources/ScribeXUI/Editor/Session.swift` | One window's model: the document, its editor, and edits routed to the two below |
| `macos/ScribeXKit/Sources/ScribeXUI/Editor/Typesetting.swift` | Builds as you type, the preview, issues, missing files, Fetch, export |
| `macos/ScribeXKit/Sources/ScribeXUI/Editor/Outline.swift` | The headings and counts the sidebar shows |
| `macos/ScribeXKit/Sources/ScribeXUI/App/Commands.swift` | Every command, defined once for the menu bar and the ⌘K palette |
| `macos/ScribeXKit/Sources/ScribeXUI/App/MenuBar.swift` | Lays the commands out in the menus, acting on the front window through `@FocusedValue` |
| `macos/ScribeXKit/Sources/ScribeXUI/Editor/Editor.swift` | STTextView setup, LaTeX colouring, brackets, completion |
| `macos/ScribeXKit/Sources/ScribeXUI/Editor/Renderer.swift` | The preview column: PDFKit pages that keep their scroll position across rebuilds, zoom, Export |
| `macos/ScribeXKit/Sources/ScribeXUI/App/Style.swift` | The book look over native controls: colours, fonts, `scribeStyle()` |
| `macos/licenses/` | Third-party licences, shipped inside the app |

## Licences

Third-party licences ship in `Contents/Resources/licenses/`; see
[THIRD-PARTY-NOTICES.md](macos/licenses/THIRD-PARTY-NOTICES.md). Portions of
this software are copyright © 2026 The FreeType Project
(https://freetype.org). All rights reserved.

The editor, STTextView, is available under the GPL v3 or a commercial
licence. Distributing ScribeX as closed source needs the commercial one.

## Before changing anything

1. **Typesetting must stay in the worker process.** A failed run leaves
   Tectonic's C globals dirty, and the next run in the same process aborts
   through a panic that can't unwind. Run in the app's process, that takes
   down the whole app.
2. **`tectonic` is pinned to a git commit, not crates.io.** The published 0.15.0
   doesn't compile against its own published sibling crates.

Both are explained in [docs/OFFLINE.md](docs/OFFLINE.md).
