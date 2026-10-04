fn main() {
    // The app bundles Tectonic's libraries in Contents/Frameworks, beside the
    // Contents/MacOS this binary runs from.
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        println!(
            "cargo:rustc-link-arg-bin=scribex-typeset=-Wl,-rpath,@executable_path/../Frameworks"
        );
    }
}
