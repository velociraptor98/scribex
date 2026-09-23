# Offline behaviour

ScribeX typesets with [Tectonic](https://tectonic-typesetting.github.io/) linked
directly into the app. There is no TeX Live installation, no `pdflatex` on
`PATH`, and no server. What there *is* is a resource cache, and understanding it
is most of understanding the product.

## The cache is the product

Tectonic ships engines, not content. Packages (`.sty`), fonts, and format files
come from a *bundle* — normally fetched over the network on first use and cached
under `~/Library/Caches/TectonicProject.Tectonic` (macOS).

With the **Offline** toggle on (the default), the bundle refuses all network
access. Anything not already cached fails the build. Measured on a cold cache:

| Document | Offline | Result |
|---|---|---|
| `article`, no title | yes | works, ~700 ms |
| `article` + `\maketitle` | yes | **fails** — `lmroman17-regular` not cached |
| same, once online | no | works in ~2.5 s, caches the font |
| same, offline again | yes | works, ~700 ms |
| `\usepackage{tikz}` | yes | **fails** — `tikz.sty` not cached |

A hello-world document pulls ~41 MB; adding TikZ pulls ~2 MB more.

Two failure shapes matter, and they read very differently in the log:

```
! LaTeX Error: File `tikz.sty' not found.
! Font TU/lmr/m/n/17.28=[lmroman17-regular]:mapping=tex-text; at 17.28pt
  not loadable: Metric (TFM) file or installed font not found.
```

The font form carries no backtick-quoted filename, so `missing_file_from_log`
in `engine.rs` needs a separate rule for it. TeX also hard-wraps the log at ~79
columns, splitting messages mid-word — the parser joins lines before matching.

**Consequence:** shipping the app without a primed cache means a user's first
offline document fails on `\maketitle`. `warmup_cache` compiles a document
exercising the common package and font set to avoid that. It needs the network
once. Deciding what else belongs in a shipped bundle is the main open design
question — see "Next" below.

## First launch

On an empty cache nothing builds at all, not even `hello world`: the engine
fails with `failed to open input file "tectonic-format-latex.tex"` before any
package is read, so there is no missing file for the banner to offer. The app
treats that failure as "not set up yet" (`isColdCache` in `App.tsx`) and asks
for a one-time download instead of reporting a build error.

The download (`warmup_cache`) builds `WARMUP` and then each plate with the
network allowed, so every document the app offers works offline afterwards.
On success it writes a `cache-ready` marker in the app data directory; the
start screen offers the download for as long as that marker is absent. It is
one click rather than automatic, because the offline toggle promises no
network access the user did not ask for.

Measured from an empty cache (September 2026):

| Step | Files | Time |
|---|---|---|
| `WARMUP` | 326 | 77 s |
| Letter, Thesis plates | 3 | ~3 s |
| Beamer plate | 114 | 28 s |
| **Total** | **~443 (45 MB)** | **~105 s** |

Downloads are strictly sequential inside Tectonic, which is why this is slow.
Progress comes from the `fetching` event sent for each downloaded file (see `worker.rs`); `SETUP_FILES` in
`Setup.tsx` is the expected total and only paces the bar.

To reproduce a first launch without touching the real cache, point
`TECTONIC_CACHE_DIR` at an empty directory and delete the `cache-ready` marker.

## Why typesetting runs in a subprocess

`engine.rs` must only be called from the worker process (`scribex --typeset`).
Tectonic's C engines keep global state. After a *failed* xdvipdfmx run, the
cleanup path (`pdf_obj_reset_global_state`) closes an output handle that no
longer exists, and the next run in that process panics here:

```
bridge_core/src/lib.rs:599  self.output_handles[id.idx()].take().unwrap()
    index out of bounds: the len is 0 but the index is 0
```

That panic crosses `extern "C"` (`ttbc_output_close`), which cannot unwind, so
it **aborts the process**. Linking the engine into the GUI directly means one
bad document takes the whole editor down with it — observed, not theorised.

Upstream's CLI never trips over this because it runs one process per document.
`worker.rs` does the same: the GUI re-executes its own binary with `--typeset`
and speaks JSON over stdio. Re-exec rather than a separate sidecar binary means
nothing extra to bundle, sign, or notarize. Spawn overhead is a few ms against a
~700 ms compile, and each run starts from clean engine state.

If a worker dies without writing a response, `worker::run` reports it as an
engine crash and the editor keeps running.

## Dependency pinning

`Cargo.toml` pins `tectonic` to a git commit on `master`, not crates.io. The published
0.15.0 does not compile against the currently published sibling crates:
`tectonic_bundles` 0.4.2 changed the `Bundle` trait (`all_files` lost its
`status` argument and gained a `Result`), producing 17 errors across
`docmodel.rs`, `config.rs`, and `driver.rs`. Pinning `tectonic_bundles` to 0.4.1
instead fails differently — it references `app_dirs::app_dirs2`, which no longer
exists. The git workspace is internally consistent. Revisit on the next release.

## Next

- Decide the shipped bundle: tiered (core / extended / full) vs. warmup-only.
  Resolve package dependencies from TeX Live's `texlive.tlpdb`.
- Pin a bundle version so builds are reproducible across machines.
- SyncTeX for click-to-source both ways.
- Show cache size and let the user pre-fetch named packages while online.
