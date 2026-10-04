//! ScribeX's typesetting engine: Tectonic, driven one job per process.
//!
//! `engine` must only run inside a worker process; `worker` is the protocol
//! the front ends use to start one. See docs/OFFLINE.md.

pub mod engine;
pub mod worker;
