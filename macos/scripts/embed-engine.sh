#!/bin/sh
# The worker finds its libraries through @executable_path/../Frameworks, an
# rpath engine/build.rs gives it. Everything is signed here with the app's
# identity, because Xcode signs only what it copied itself.
set -eu

root=$(cd "$SRCROOT/.." && pwd)
brew=$(PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" command -v brew) || {
    echo "error: Homebrew is needed for the libraries Tectonic links against; see README" >&2
    exit 1
}
prefix=$("$brew" --prefix)
pkg_config_path=${PKG_CONFIG_PATH:-"$("$brew" --prefix icu4c)/lib/pkgconfig:$("$brew" --prefix openssl@3)/lib/pkgconfig:$prefix/lib/pkgconfig"}
tools="$prefix/bin:$HOME/.cargo/bin:/usr/bin:/bin:/usr/sbin:/sbin"

case "$CONFIGURATION" in
    Release) profile=release; release=--release ;;
    *) profile=debug; release= ;;
esac

# A clean environment: Xcode exports SDKROOT, MACOSX_DEPLOYMENT_TARGET and
# more, which change cargo's fingerprints and would rebuild Tectonic's C from
# scratch, and again on the next build from a terminal.
env -i HOME="$HOME" PATH="$tools" PKG_CONFIG_PATH="$pkg_config_path" \
    cargo build --manifest-path "$root/Cargo.toml" -p scribex-engine --bin scribex-typeset $release

app="$TARGET_BUILD_DIR/$WRAPPER_NAME"
macos="$app/Contents/MacOS"
frameworks="$app/Contents/Frameworks"
worker="$macos/scribex-typeset"

env -i HOME="$HOME" PATH="$tools" PKG_CONFIG_PATH="$pkg_config_path" \
    sh "$SRCROOT/scripts/stage-dylibs.sh" "$frameworks"

mkdir -p "$macos"
cp -f "$root/target/$profile/scribex-typeset" "$worker"
chmod u+w "$worker"

# Point the worker at the bundled copies instead of wherever it was linked from.
otool -L "$worker" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    name=$(basename "$dep")
    if [ -e "$frameworks/$name" ] && [ "$dep" != "@rpath/$name" ]; then
        install_name_tool -change "$dep" "@rpath/$name" "$worker" 2>/dev/null
    fi
done
leftover=$(otool -L "$worker" | tail -n +2 | awk '{print $1}' | grep -v '^/usr/lib/\|^/System/\|^@rpath/' || true)
if [ -n "$leftover" ]; then
    echo "error: scribex-typeset still links libraries that are not bundled:" >&2
    echo "$leftover" >&2
    exit 1
fi

licenses="$app/Contents/Resources/licenses"
rm -rf "$licenses"
cp -R "$SRCROOT/licenses" "$licenses"

# Sign with the identity Xcode signs the app with ("-" when signing to run
# locally). The hardened runtime's library validation refuses ad-hoc signed
# libraries, so it is only asked for when the build enables it (Release) and
# there is a real identity to sign with — which notarization needs anyway.
identity=${EXPANDED_CODE_SIGN_IDENTITY:-}
[ -n "$identity" ] || identity=-
runtime=
if [ "${ENABLE_HARDENED_RUNTIME:-NO}" = YES ] && [ "$identity" != - ]; then
    runtime="--options runtime --timestamp"
fi
for lib in "$frameworks"/*.dylib; do
    codesign --force --sign "$identity" $runtime "$lib"
done
codesign --force --sign "$identity" $runtime "$worker"
