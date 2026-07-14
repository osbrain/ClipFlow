#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${1:-$REPO_ROOT/artifacts/ClipFlow.app}"
PLIST="$APP_PATH/Contents/Info.plist"
EXECUTABLE="$APP_PATH/Contents/MacOS/ClipFlowApp"
RESOURCE_BUNDLE="$APP_PATH/Contents/Resources/ClipFlow_ClipFlowUI.bundle"

[[ -d "$APP_PATH" ]]
[[ -f "$PLIST" ]]
[[ -x "$EXECUTABLE" ]]
[[ -d "$RESOURCE_BUNDLE" ]]
[[ ! -e "$APP_PATH/ClipFlow_ClipFlowUI.bundle" ]]

/usr/bin/plutil -lint "$PLIST" >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" == "com.aiesst.clipflow" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")" == "ClipFlowApp" ]]
/usr/bin/codesign --verify --deep --strict "$APP_PATH"

SIGNING_IDENTIFIER="$(
    /usr/bin/codesign -dvv "$APP_PATH" 2>&1 \
        | /usr/bin/sed -n 's/^Identifier=//p'
)"
[[ "$SIGNING_IDENTIFIER" == "com.aiesst.clipflow" ]]

echo "CLIPFLOW_LOCAL_APP_OK"
