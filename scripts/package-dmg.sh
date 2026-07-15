#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${1:-$REPO_ROOT/artifacts/ClipFlow.app}"

[[ -d "$APP_PATH" ]]
[[ -f "$APP_PATH/Contents/Info.plist" ]]

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
OUTPUT_DMG="${2:-$REPO_ROOT/artifacts/ClipFlow-$VERSION-macos.dmg}"
OUTPUT_DIRECTORY="$(dirname "$OUTPUT_DMG")"
STAGING_ROOT="$(/usr/bin/mktemp -d "$OUTPUT_DIRECTORY/.clipflow-dmg.XXXXXX")"
VOLUME_ROOT="$STAGING_ROOT/ClipFlow"
STAGING_DMG="$STAGING_ROOT/ClipFlow.dmg"

cleanup() {
    /bin/rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

/bin/mkdir -p "$OUTPUT_DIRECTORY" "$VOLUME_ROOT"
/usr/bin/ditto "$APP_PATH" "$VOLUME_ROOT/ClipFlow.app"
/bin/ln -s /Applications "$VOLUME_ROOT/Applications"

/usr/bin/printf '%s\n' \
    'ClipFlow test distribution' \
    '' \
    '1. Drag ClipFlow.app onto the Applications alias.' \
    '2. Open ClipFlow from Applications.' \
    '' \
    'This is an Ad-hoc-signed test build, not a notarized public release.' \
    'If macOS blocks the app, open System Settings > Privacy & Security and choose Open Anyway.' \
    'Only install it when you trust the source.' \
    > "$VOLUME_ROOT/README.txt"

/usr/bin/hdiutil create \
    -ov \
    -format UDZO \
    -volname ClipFlow \
    -srcfolder "$VOLUME_ROOT" \
    "$STAGING_DMG" >/dev/null
/usr/bin/hdiutil verify "$STAGING_DMG" >/dev/null
/bin/rm -f "$OUTPUT_DMG"
/bin/mv "$STAGING_DMG" "$OUTPUT_DMG"

echo "Packaged $OUTPUT_DMG (Ad-hoc-signed test distribution)"
