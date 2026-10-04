#!/bin/sh
# Stage the libraries Tectonic links against into frameworks/ (see
# scripts/stage-dylibs.sh), then write tauri.macos.conf.json, which Tauri
# merges into tauri.conf.json on macOS, listing them and the minimum macOS
# version they require.
set -eu

cd "$(dirname "$0")/.."
out=frameworks
sh ../scripts/stage-dylibs.sh "$out"

minos=0
for lib in "$out"/*.dylib; do
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
