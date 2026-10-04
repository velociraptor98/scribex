fn main() {
    // The macOS app ships the libraries Tectonic links against in
    // Contents/Frameworks, beside the Contents/MacOS this binary runs from.
    // Outside a bundle the rpath is unused: the linked paths still resolve.
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        println!("cargo:rustc-link-arg-bin=scribex-typeset=-Wl,-rpath,@executable_path/../Frameworks");
    }
}
