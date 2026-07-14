#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURATION="${1:-debug}"
BUNDLE_ID="com.aiesst.clipflow"
OUTPUT_ROOT="$REPO_ROOT/artifacts"
OUTPUT_APP="$OUTPUT_ROOT/ClipFlow.app"

case "$CONFIGURATION" in
    debug)
        BUILD_OPTIONS=(-c debug)
        ;;
    release)
        BUILD_OPTIONS=(-c release)
        ;;
    *)
        echo "usage: $0 [debug|release]" >&2
        exit 2
        ;;
esac

cd "$REPO_ROOT"
/usr/bin/swift build "${BUILD_OPTIONS[@]}" --product ClipFlowApp
BIN_PATH="$(/usr/bin/swift build "${BUILD_OPTIONS[@]}" --show-bin-path)"
SOURCE_EXECUTABLE="$BIN_PATH/ClipFlowApp"
SOURCE_RESOURCE_BUNDLE="$BIN_PATH/ClipFlow_ClipFlowUI.bundle"

[[ -x "$SOURCE_EXECUTABLE" ]]
[[ -d "$SOURCE_RESOURCE_BUNDLE" ]]
/usr/bin/plutil -lint "$REPO_ROOT/Config/Info.plist" >/dev/null

/bin/mkdir -p "$OUTPUT_ROOT"
STAGING_ROOT="$(/usr/bin/mktemp -d "$OUTPUT_ROOT/.clipflow-package.XXXXXX")"
STAGING_APP="$STAGING_ROOT/ClipFlow.app"
trap '/bin/rm -rf "$STAGING_ROOT"' EXIT

/bin/mkdir -p \
    "$STAGING_APP/Contents/MacOS" \
    "$STAGING_APP/Contents/Resources" \
    "$STAGING_APP/Contents/Resources/zh-Hans.lproj"
/usr/bin/ditto "$REPO_ROOT/Config/Info.plist" "$STAGING_APP/Contents/Info.plist"
/usr/bin/ditto "$SOURCE_EXECUTABLE" "$STAGING_APP/Contents/MacOS/ClipFlowApp"
/bin/chmod 755 "$STAGING_APP/Contents/MacOS/ClipFlowApp"
/usr/bin/ditto \
    "$SOURCE_RESOURCE_BUNDLE" \
    "$STAGING_APP/Contents/Resources/ClipFlow_ClipFlowUI.bundle"
/usr/bin/ditto \
    "$REPO_ROOT/Config/zh-Hans.lproj/InfoPlist.strings" \
    "$STAGING_APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
/usr/bin/printf 'APPL????' > "$STAGING_APP/Contents/PkgInfo"

/usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    --identifier "$BUNDLE_ID" \
    "$STAGING_APP"

"$SCRIPT_DIR/verify-local-app.sh" "$STAGING_APP"
/bin/rm -rf "$OUTPUT_APP"
/bin/mv "$STAGING_APP" "$OUTPUT_APP"

echo "Packaged $OUTPUT_APP ($CONFIGURATION, Ad-hoc signed)"
