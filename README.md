# ScribeX

An offline LaTeX editor for macOS: a native Swift app (SwiftUI, STTextView,
PDFKit) over [Tectonic](https://tectonic-typesetting.github.io/), which is
driven from Rust. No TeX Live installation or server is needed.

## Features

- Open, edit, save (⌘S), save as (⇧⌘S) and export to PDF (⌘E).
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
`macos/build/dist/ScribeX-<version>.dmg`. Run without settings, it signs ad
hoc: the DMG works on this Mac and Gatekeeper refuses it on others.

A DMG other Macs will open needs a paid Apple Developer account, set up once:

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
| `macos/ScribeXKit/Sources/ScribeXCore/Typesetter.swift` | Runs builds in the worker, one at a time; first-run download |
| `macos/ScribeXKit/Sources/ScribeXCore/DocumentFiles.swift` | Save and export, the only writes to the user's files |
| `macos/ScribeXKit/Sources/ScribeXCore/TexLog.swift` | Parses the TeX log into issues and the press log |
| `macos/ScribeXKit/Sources/ScribeXCore/Latex.swift` | Outline, document counts, bibliography keys |
| `macos/ScribeXKit/Sources/ScribeXCore/Snippets.swift` | Plain-English → LaTeX snippet matcher |
| `macos/ScribeXKit/Sources/ScribeXUI/AppModel.swift` | App state, builds, file handling, autosave |
| `macos/ScribeXKit/Sources/ScribeXUI/AppShell.swift` | The window, the unsaved-changes guard, the menu bar |
| `macos/ScribeXKit/Sources/ScribeXUI/SourceEditor.swift` | STTextView setup, LaTeX colouring, brackets, completion |
| `macos/ScribeXKit/Sources/ScribeXUI/PreviewView.swift` | PDFKit preview; keeps scroll position across rebuilds |
| `macos/ScribeXKit/Sources/ScribeXUI/Theme.swift` | Design tokens, fonts and controls |
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
