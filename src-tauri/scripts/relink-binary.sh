#!/bin/sh
# Point the compiled binary at the libraries bundled in Contents/Frameworks
# instead of wherever they were linked from. Run by Tauri as
# beforeBundleCommand, after cargo has linked the binary and before it is
# copied into the .app.
set -eu

cd "$(dirname "$0")/.."

for bin in target/release/scribex target/debug/scribex target/*/release/scribex target/*/debug/scribex; do
    [ -f "$bin" ] || continue
    otool -L "$bin" | tail -n +2 | awk '{print $1}' | while read -r dep; do
        name=$(basename "$dep")
        if [ -e "frameworks/$name" ] && [ "$dep" != "@rpath/$name" ]; then
            install_name_tool -change "$dep" "@rpath/$name" "$bin" 2>/dev/null
        fi
    done
    leftover=$(otool -L "$bin" | tail -n +2 | awk '{print $1}' | grep -v '^/usr/lib/\|^/System/\|^@rpath/' || true)
    if [ -n "$leftover" ]; then
        echo "relink-binary: $bin still links libraries that are not bundled:" >&2
        echo "$leftover" >&2
        exit 1
    fi
    codesign --force --sign - "$bin" >/dev/null 2>&1
done
