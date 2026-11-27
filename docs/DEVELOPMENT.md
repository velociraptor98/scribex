# Developing ScribeX

[Overview](../README.md) · **Development** · [Offline behaviour](OFFLINE.md)

How ScribeX is put together, how to build, test and ship it, and where to go
to change things.

- [Architecture](#architecture)
- [Building](#building)
- [Testing](#testing)
- [Distributing](#distributing)
- [Where to make changes](#where-to-make-changes)
- [Project layout](#project-layout)
- [Before changing anything](#before-changing-anything)
- [Licences](#licences)

## Architecture

ScribeX is a native Swift app (SwiftUI, [STTextView](https://github.com/krzyzanowskim/STTextView),
PDFKit) over [Tectonic](https://tectonic-typesetting.github.io/), which is
driven from Rust.

```
ScribeX.app
├── Contents/MacOS/ScribeX           Swift app: windows, editor, preview
├── Contents/MacOS/scribex-typeset   Rust worker: one Tectonic build per launch
├── Contents/Frameworks/             ICU, FreeType, Graphite2, libpng (from Homebrew)
└── Contents/Resources/licenses/     Third-party licences
```

- **`engine/`** (Rust) wraps Tectonic and builds the `scribex-typeset` worker.
  The app sends it one JSON request on stdin and reads one response back.
- **`macos/ScribeXKit/`** (Swift package) holds nearly all the app's code:
  - `ScribeXCore`: no UI. Running the worker, reading the TeX log, outline,
    completions, highlighting, snippets, templates, export.
  - `ScribeXUI`: SwiftUI and AppKit. The welcome window, document windows,
    editor, preview, ⌘K palette, menu bar.
- **`macos/ScribeX/`** is the app target. It's little more than an entry point
  and the icon.

The preview never writes to your document. The engine typesets the editor
buffer from memory, so the file on disk only changes when you save. `\input`
and `\includegraphics` still resolve relative to the document's folder.

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

If `xcodebuild` says the active developer directory is a command line tools
instance, point it at Xcode, either for one command with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` or for good with
`sudo xcode-select -s /Applications/Xcode.app`.

The first build compiles Tectonic's vendored C and takes several minutes.

**The first run needs the network once.** On a cold cache even `\maketitle`
fails offline, because its display-size font isn't cached. Click **Download
now** when the app offers it. [OFFLINE.md](OFFLINE.md) has the details.

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

Debug builds are ad-hoc signed and run on the building machine only. Release
builds turn on the hardened runtime, which notarization needs. With ad-hoc
signing the worker is left without it, because its library validation rejects
ad-hoc signed libraries.

The app is built for Apple Silicon only. The worker and the Homebrew libraries
are built for the machine that builds them, so the app target is pinned to
arm64 to match.

## Testing

```sh
cargo test -p scribex-engine               # the engine, including the worker binary
cargo build -p scribex-engine              # the worker the Swift integration tests run
cd macos/ScribeXKit && swift test          # everything but the app shell
```

Tests that typeset need a primed Tectonic cache, since they build offline.
Without one they report that they were skipped.

### Driving the app from a script

Debug builds can drive themselves and render their window to PNGs, with no
Screen Recording permission needed. See
`macos/ScribeXKit/Sources/ScribeXUI/App/DebugScript.swift` for every step.

```sh
SCRIBEX_DEBUG_SCRIPT="snap welcome; new; wait 3; snap editor; quit" \
SCRIBEX_DEBUG_OUT=/tmp/shots \
  macos/build/DerivedData/Build/Products/Debug/ScribeX.app/Contents/MacOS/ScribeX
```

The window snapshot doesn't capture PDFKit's page tiles. Use `page NAME` to
render the preview's first page on its own.

## Distributing

`macos/scripts/make-dmg.sh` builds a Release app and packages it as
`macos/build/dist/ScribeX-<version>.dmg`.

### Versioning

Before each release, raise both of these:

| Setting | Where |
|---|---|
| `MARKETING_VERSION` (e.g. `0.0.7-alpha`) | Xcode target ScribeX, both Debug and Release configurations (`macos/ScribeX.xcodeproj/project.pbxproj`) |
| `CURRENT_PROJECT_VERSION` (build number) | Same place |
| `version` | `engine/Cargo.toml`. Keep it matching. `Cargo.lock` follows on the next cargo build |

Also check the STTextView licence under [Licences](#licences).

### Without an Apple Developer account

Run the script with no settings. The app is signed ad hoc, which is enough to
share. The first time someone opens it, macOS blocks it ("Apple could not
verify 'ScribeX' is free of malware"). They allow it once under System
Settings → Privacy & Security → Open Anyway, and from then on it opens
normally. On macOS 15 and later, right-click → Open no longer offers this.
Another way:

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
notarizes and staples the DMG. Because the app is stapled too, it passes
Gatekeeper after being copied out of the DMG, even offline. Each notarization
round usually takes a few minutes.

## Where to make changes

Paths under `Sources/` are in `macos/ScribeXKit/Sources/`.

| To… | Edit |
|---|---|
| Add or change a starter template | Add the `.tex` to `Sources/ScribeXCore/Content/Resources/Templates/` and list it in `templates.json` there |
| Add a ⌘K snippet ("3 by 4 table") | `Sources/ScribeXCore/Content/Resources/snippets.json`: trigger words, title, LaTeX. Snippets built from parameters (tables) use a `generator` in `Content/Snippets.swift` |
| Add a menu command or palette action | `Command.all` in `Sources/ScribeXUI/App/Commands.swift`. Its `menu` decides where it appears, and `MenuBar.swift` lays the menus out |
| Explain a TeX error in plain English, or offer a fix | `Sources/ScribeXCore/Latex/Issues.swift`. Problems caught before a build (such as a command defined in terms of itself) go in `Latex/SourceChecks.swift` |
| Add a command or environment to autocomplete | `Sources/ScribeXCore/Latex/Completions.swift` |
| Change syntax colouring | Tokens in `Sources/ScribeXCore/Latex/Highlighting.swift`; colours in `Sources/ScribeXUI/Editor/Editor.swift` |
| Change colours, fonts or the overall look | `Sources/ScribeXUI/App/Style.swift`. Bundled fonts are in `Sources/ScribeXUI/Fonts/` |
| Change an export option (paper size, links) | `Sources/ScribeXCore/Exporting.swift`, and the sheet in `Sources/ScribeXUI/Editor/ExportSheet.swift` |
| Change when builds run, or the preview | `Sources/ScribeXUI/Editor/Typesetting.swift` and `Editor/Renderer.swift` |
| Change the welcome window | `Sources/ScribeXUI/Home/` |
| Change how Tectonic is called | `engine/src/engine.rs`, and the request/response in `engine/src/worker.rs`. The Swift side is `Sources/ScribeXCore/Typesetter.swift` |
| Bundle another Homebrew library | `macos/scripts/stage-dylibs.sh`, and add its licence to `macos/licenses/` |

## Project layout

| Path | Role |
|---|---|
| `engine/src/engine.rs` | Tectonic driver. Worker process only (see [below](#before-changing-anything)) |
| `engine/src/worker.rs` | The worker protocol: one JSON request in, one response out |
| `engine/src/bin/scribex-typeset.rs` | The worker binary the app launches for each build |
| `macos/ScribeX/` | The app target: entry point and icon |
| `macos/scripts/` | Build phase (`embed-engine.sh`, `stage-dylibs.sh`) and packaging (`make-dmg.sh`) |
| `macos/licenses/` | Third-party licences, shipped inside the app |
| **ScribeXCore** | `macos/ScribeXKit/Sources/ScribeXCore/` |
| `Typesetter.swift` | Runs builds in the worker, one at a time per build folder, with time limits; first-run download |
| `Exporting.swift` | Export options, applied to a throwaway copy of the source |
| `Latex/Issues.swift` | Turns the TeX log into issues, with plain-English titles and fixes |
| `Latex/SourceChecks.swift` | Problems found in the source before any build, such as self-recursive macros |
| `Latex/Outline.swift` | Headings with LaTeX's numbering, document counts, the title |
| `Latex/Bibliography.swift` | Cited keys and the entries in .bib files |
| `Latex/Completions.swift` | The command and environment names the editor completes |
| `Latex/Highlighting.swift` | Tokens for syntax colouring, line by line |
| `Content/Snippets.swift` | Plain-English → LaTeX snippet matcher; vocabulary in `Resources/snippets.json` |
| `Content/Templates.swift` | Starter templates; their LaTeX is in `Resources/Templates` |
| `Content/Bundled.swift` | Loads files shipped in `Resources/` |
| **ScribeXUI** | `macos/ScribeXKit/Sources/ScribeXUI/` |
| `App/Engine.swift` | Shared by all windows: the typesetter and its download cache |
| `App/Commands.swift` | Every command, defined once for the menu bar and the ⌘K palette |
| `App/MenuBar.swift` | Lays the commands out in the menus, acting on the front window through `@FocusedValue` |
| `App/Palette.swift` | The ⌘K palette sheet: snippets and commands in one ranked list |
| `App/Setup.swift` | The one-time download of packages and fonts: a card on Home, a banner in a document |
| `App/Style.swift` | The book look over native controls: colours, fonts, `scribeStyle()` |
| `App/DebugScript.swift` | Debug builds only: scripted runs that snapshot the window |
| `Home/` | The welcome window: identity, create/open, templates, recent documents |
| `Editor/TexDocument.swift` | The .tex document type; the document system does the file handling |
| `Editor/DocumentView.swift` | One document window: contents · source · preview, and its sheets |
| `Editor/Session.swift` | One window's model: the document, its editor, and edits routed to the two below |
| `Editor/Typesetting.swift` | Builds as you type, the preview, issues, missing files, Fetch, export |
| `Editor/Outline.swift` | The headings and counts the sidebar shows |
| `Editor/Contents.swift` | The sidebar: headings that jump to their line, with a tally beneath |
| `Editor/Editor.swift` | STTextView setup, LaTeX colouring, brackets, completion |
| `Editor/Renderer.swift` | The preview column: PDFKit pages that keep their scroll position across rebuilds, zoom |
| `Editor/Issues.swift` | The issues drawer at the foot of the preview |
| `Editor/ExportSheet.swift` | The ⌘E export sheet |

## Before changing anything

1. **Typesetting must stay in the worker process.** A failed run leaves
   Tectonic's C globals dirty, and the next run in the same process aborts
   through a panic that can't unwind. In the app's process, that would take
   down the whole app.
2. **`tectonic` is pinned to a git commit, not crates.io.** The published
   0.15.0 doesn't compile against its own published sibling crates.

Both are explained in [OFFLINE.md](OFFLINE.md).

## Licences

Third-party licences ship in `Contents/Resources/licenses/`; see
[THIRD-PARTY-NOTICES.md](../macos/licenses/THIRD-PARTY-NOTICES.md). Portions of
this software are copyright © 2026 The FreeType Project
(https://freetype.org). All rights reserved.

The editor component, STTextView, is available under the GPL v3 or a
commercial licence. Distributing ScribeX as closed source needs the commercial
one.
