#!/bin/sh
# Copy the non-system libraries Tectonic links against into frameworks/, with
# @rpath install names, so the bundler can ship them inside the .app. Then
# write tauri.macos.conf.json, which Tauri merges into tauri.conf.json on macOS,
# listing them and the minimum macOS version they require.
#
# Libraries are found through pkg-config, as Tectonic's own build finds them,
# so nothing here depends on where Homebrew lives or on library versions.
set -eu

cd "$(dirname "$0")/.."
out=frameworks
MODULES="icu-uc freetype2 graphite2 libpng16"

is_system() {
    case "$1" in /usr/lib/*|/System/*) return 0;; *) return 1;; esac
}

# The real file behind -l<name> in the module's -L directory.
module_libs() {
    flags=$(pkg-config --libs-only-L --libs-only-l "$1") || {
        echo "stage-dylibs: pkg-config cannot find $1 (is PKG_CONFIG_PATH set? see README)" >&2
        exit 1
    }
    dir=""
    for f in $flags; do
        case "$f" in -L*) [ -n "$dir" ] || dir=${f#-L};; esac
    done
    for f in $flags; do
        case "$f" in
            -l*)
                lib="$dir/lib${f#-l}.dylib"
                [ -e "$lib" ] || { echo "stage-dylibs: missing $lib" >&2; exit 1; }
                echo "$lib"
                ;;
        esac
    done
}

# Non-system libraries `$1` loads, as absolute paths.
deps_of() {
    dir=$(dirname "$1")
    otool -L "$1" | tail -n +3 | awk '{print $1}' | while read -r dep; do
        case "$dep" in
            @loader_path/*) echo "$dir/${dep#@loader_path/}" ;;
            @rpath/*) echo "$dir/${dep#@rpath/}" ;;
            /*) is_system "$dep" || echo "$dep" ;;
        esac
    done
}

rm -rf "$out"
mkdir -p "$out"

queue=""
for m in $MODULES; do queue="$queue $(module_libs "$m")"; done

# Copy each library under its install name (e.g. libicuuc.78.dylib, not the
# libicuuc.dylib symlink), following dependencies until none are left.
while [ -n "$(echo $queue)" ]; do
    next=""
    for src in $queue; do
        name=$(basename "$(otool -D "$src" | tail -n 1)")
        [ -e "$out/$name" ] && continue
        cp -L "$src" "$out/$name"
        next="$next $(deps_of "$src")"
    done
    queue=$next
done

minos=0
for lib in "$out"/*.dylib; do
    chmod u+w "$lib"
    install_name_tool -id "@rpath/$(basename "$lib")" "$lib" 2>/dev/null
    otool -L "$lib" | tail -n +3 | awk '{print $1}' | while read -r dep; do
        name=$(basename "$dep")
        if [ -e "$out/$name" ] && [ "$dep" != "@rpath/$name" ]; then
            install_name_tool -change "$dep" "@rpath/$name" "$lib" 2>/dev/null
        fi
    done
    codesign --force --sign - "$lib" >/dev/null 2>&1
    v=$(otool -l "$lib" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')
    minos=$(printf '%s\n%s\n' "$minos" "${v:-0}" | sort -t. -k1,1n -k2,2n | tail -n 1)
done

list=$(ls "$out" | sed "s|^|        \"$out/|; s|\$|\",|" | sed '$ s/,$//')
conf=$(cat <<EOF
{
  "bundle": {
    "macOS": {
      "minimumSystemVersion": "$minos",
      "frameworks": [
$list
      ]
    }
  }
}
EOF
)
# Rewrite only on change, so an unchanged config does not trigger a rebuild.
[ "$(cat tauri.macos.conf.json 2>/dev/null)" = "$conf" ] || printf '%s\n' "$conf" > tauri.macos.conf.json
