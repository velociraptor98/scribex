#!/bin/sh
# Build a Release ScribeX.app and package it as build/dist/ScribeX-<version>.dmg.
#
#   SIGNING_IDENTITY  "Developer ID Application: Name (TEAMID)". Without it the
#                     app is signed ad hoc: it runs on this Mac, and Gatekeeper
#                     refuses it everywhere else.
#   NOTARY_PROFILE    A notarytool keychain profile (see README). With both set,
#                     the app and the DMG are notarized and stapled, so they open
#                     on any Mac, offline too.
set -eu

cd "$(dirname "$0")/.."
identity=${SIGNING_IDENTITY:-}
profile=${NOTARY_PROFILE:-}
derived=build/DerivedData
out=build/dist
app=$derived/Build/Products/Release/ScribeX.app

if [ -n "$identity" ]; then
    team=$(printf '%s' "$identity" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')
    [ -n "$team" ] || { echo "error: SIGNING_IDENTITY should end in (TEAMID)" >&2; exit 1; }
    set -- CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" OTHER_CODE_SIGN_FLAGS=--timestamp
else
    echo "warning: no SIGNING_IDENTITY; signing ad hoc, for this Mac only" >&2
    set --
fi
if [ -n "$profile" ] && [ -z "$identity" ]; then
    echo "error: notarization needs SIGNING_IDENTITY as well" >&2
    exit 1
fi

xcodebuild -project ScribeX.xcodeproj -scheme ScribeX -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived" -quiet \
    clean build "$@"

codesign --verify --deep --strict "$app"
version=$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")
mkdir -p "$out"
dmg=$out/ScribeX-$version.dmg

notarize() {
    result=$(xcrun notarytool submit "$1" --keychain-profile "$profile" --wait --output-format json)
    status=$(printf '%s' "$result" | plutil -extract status raw -)
    if [ "$status" != Accepted ]; then
        id=$(printf '%s' "$result" | plutil -extract id raw -)
        echo "error: notarization of $1 was $status; see: xcrun notarytool log $id --keychain-profile $profile" >&2
        exit 1
    fi
}

# The app is stapled as well as the DMG: once copied out of the DMG it must
# still pass Gatekeeper with no network, which an offline editor will meet.
if [ -n "$profile" ]; then
    zip=$out/ScribeX-$version.zip
    ditto -c -k --keepParent "$app" "$zip"
    notarize "$zip"
    rm -f "$zip"
    xcrun stapler staple "$app"
fi

staging=$(mktemp -d)
ditto "$app" "$staging/ScribeX.app"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname "ScribeX $version" -srcfolder "$staging" -format UDZO -quiet "$dmg"
rm -rf "${staging:?}"

if [ -n "$identity" ]; then
    codesign --sign "$identity" --timestamp "$dmg"
fi
if [ -n "$profile" ]; then
    notarize "$dmg"
    xcrun stapler staple "$dmg"
    spctl --assess --type open --context context:primary-signature -v "$dmg"
fi

echo "$(pwd)/$dmg"
