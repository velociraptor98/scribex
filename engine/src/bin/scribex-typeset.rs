//! `--warmup-document` prints the document that primes the offline cache, so
//! the app can build it without keeping its own copy.

// Tectonic's vendored C declares a common symbol with 32 KB alignment, which ld
// notes it has to reduce. Harmless, and nothing here can change it.
#![allow(linker_messages)]

fn main() {
    if std::env::args().any(|a| a == "--warmup-document") {
        print!("{}", scribex_engine::engine::WARMUP);
        return;
    }
    scribex_engine::worker::main()
}
