//! The worker the macOS app launches for each build: one JSON request on
//! stdin, one JSON response on stdout, download progress on stderr. Same
//! protocol as `scribex --typeset`; see `worker.rs`.
//!
//! `--warmup-document` prints the document that primes the offline cache
//! instead, so the app builds it like any other without keeping its own copy.

fn main() {
    if std::env::args().any(|a| a == "--warmup-document") {
        print!("{}", scribex_engine::engine::WARMUP);
        return;
    }
    scribex_engine::worker::main()
}
