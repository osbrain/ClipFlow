#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$REPO_ROOT/artifacts/ClipFlow.app"
TEMP_ROOT="$(/usr/bin/mktemp -d)"
OUTPUT_DMG="$TEMP_ROOT/ClipFlow-test.dmg"
MOUNT_POINT="$TEMP_ROOT/mount"

cleanup() {
    if /usr/bin/hdiutil info | /usr/bin/grep -Fq "$MOUNT_POINT"; then
        /usr/bin/hdiutil detach "$MOUNT_POINT" -quiet || true
    fi
    /bin/rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

[[ -x "$REPO_ROOT/scripts/package-dmg.sh" ]]
[[ -d "$APP_PATH" ]]

"$REPO_ROOT/scripts/package-dmg.sh" "$APP_PATH" "$OUTPUT_DMG"

[[ -f "$OUTPUT_DMG" ]]
/usr/bin/hdiutil verify "$OUTPUT_DMG"
/bin/mkdir "$MOUNT_POINT"
/usr/bin/hdiutil attach "$OUTPUT_DMG" -nobrowse -mountpoint "$MOUNT_POINT" -quiet

[[ -d "$MOUNT_POINT/ClipFlow.app" ]]
[[ -L "$MOUNT_POINT/Applications" ]]
[[ "$(/usr/bin/readlink "$MOUNT_POINT/Applications")" == "/Applications" ]]
[[ -f "$MOUNT_POINT/README.txt" ]]

echo "CLIPFLOW_DMG_OK"
