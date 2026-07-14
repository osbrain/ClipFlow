#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/artifacts/visual-acceptance"
DEFAULT_APP_EXECUTABLE="$REPO_ROOT/.build/debug/ClipFlowApp"
APP_EXECUTABLE="${CLIPFLOW_APP_EXECUTABLE:-$DEFAULT_APP_EXECUTABLE}"
RUN_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/clipflow-visual-acceptance.XXXXXX")"
HELPER_SOURCE="$RUN_ROOT/window-id.swift"
HELPER_EXECUTABLE="$RUN_ROOT/window-id"
LAUNCHED_PID=""
SCENARIO_INDEX=0

cleanup_launched_process() {
    if [[ -n "$LAUNCHED_PID" ]] && kill -0 "$LAUNCHED_PID" 2>/dev/null; then
        kill -TERM "$LAUNCHED_PID" 2>/dev/null || true
        for _ in {1..20}; do
            if ! kill -0 "$LAUNCHED_PID" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done
        if kill -0 "$LAUNCHED_PID" 2>/dev/null; then
            kill -KILL "$LAUNCHED_PID" 2>/dev/null || true
        fi
    fi
    if [[ -n "$LAUNCHED_PID" ]]; then
        wait "$LAUNCHED_PID" 2>/dev/null || true
    fi
    LAUNCHED_PID=""
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    cleanup_launched_process
    rm -rf "$RUN_ROOT"
    exit "$status"
}
trap cleanup EXIT INT TERM

if [[ -z "${CLIPFLOW_APP_EXECUTABLE:-}" ]]; then
    (
        cd "$REPO_ROOT"
        swift build --product ClipFlowApp
    )
fi

if [[ ! -x "$APP_EXECUTABLE" ]]; then
    cat >&2 <<EOF
ClipFlowApp Debug executable was not found or is not executable:
  $APP_EXECUTABLE

Build it with:
  cd "$REPO_ROOT" && swift build --product ClipFlowApp

Or point this script at another Debug executable that supports the acceptance probe:
  CLIPFLOW_APP_EXECUTABLE=/absolute/path/to/ClipFlowApp $0
EOF
    exit 1
fi

static_acceptance_capability_check() {
    if ! /usr/bin/strings -a "$APP_EXECUTABLE" \
        | /usr/bin/grep -Fx "CLIPFLOW_VISUAL_ACCEPTANCE_V1" >/dev/null; then
        cat >&2 <<EOF
ClipFlowApp was rejected without being launched because it does not contain
the exact Debug visual-acceptance marker:
  CLIPFLOW_VISUAL_ACCEPTANCE_V1

Candidate executable:
  $APP_EXECUTABLE

Use a freshly built Debug executable. Release builds intentionally omit this
marker and cannot be used for visual-acceptance capture.
EOF
        return 1
    fi
}

static_acceptance_capability_check

if [[ "${CLIPFLOW_ACCEPTANCE_STATIC_CHECK_ONLY:-}" == "1" ]]; then
    echo "CLIPFLOW_STATIC_ACCEPTANCE_OK"
    exit 0
fi

if [[ ! -x /usr/sbin/screencapture ]]; then
    echo "Required macOS tool /usr/sbin/screencapture is unavailable." >&2
    exit 1
fi

run_acceptance_probe() {
    local standard_output="$RUN_ROOT/probe.stdout"
    local standard_error="$RUN_ROOT/probe.stderr"
    local probe_output=""
    local probe_status=0
    local completed=0

    "$APP_EXECUTABLE" --clipflow-acceptance-probe \
        >"$standard_output" 2>"$standard_error" &
    LAUNCHED_PID=$!

    for _ in {1..40}; do
        if ! kill -0 "$LAUNCHED_PID" 2>/dev/null; then
            completed=1
            break
        fi
        sleep 0.1
    done

    if [[ "$completed" != "1" ]]; then
        echo "ClipFlowApp acceptance probe did not exit within 4 seconds." >&2
        cleanup_launched_process
        return 1
    fi

    if wait "$LAUNCHED_PID"; then
        probe_status=0
    else
        probe_status=$?
    fi
    LAUNCHED_PID=""
    probe_output="$(<"$standard_output")"

    if [[ "$probe_status" != "0" || "$probe_output" != "CLIPFLOW_VISUAL_ACCEPTANCE_V1" ]]; then
        echo "ClipFlowApp failed the runtime visual-acceptance capability probe." >&2
        echo "Expected exact stdout marker: CLIPFLOW_VISUAL_ACCEPTANCE_V1" >&2
        echo "Exit status: $probe_status" >&2
        if [[ -s "$standard_error" ]]; then
            echo "Probe stderr:" >&2
            sed 's/^/  /' "$standard_error" >&2
        fi
        return 1
    fi
}

run_acceptance_probe

mkdir -p "$OUTPUT_DIR"
rm -f \
    "$OUTPUT_DIR/dark-zh-wide.png" \
    "$OUTPUT_DIR/light-en-wide.png" \
    "$OUTPUT_DIR/light-en-compact.png" \
    "$OUTPUT_DIR/light-en-settings.png" \
    "$OUTPUT_DIR/dark-zh-settings.png" \
    "$OUTPUT_DIR/light-en-file-actions.png" \
    "$OUTPUT_DIR/light-en-link-actions.png" \
    "$OUTPUT_DIR/light-en-image-actions.png" \
    "$OUTPUT_DIR/light-en-text-actions.png" \
    "$OUTPUT_DIR/light-en-browser-empty.png" \
    "$OUTPUT_DIR/light-en-quick-look.png"

cat >"$HELPER_SOURCE" <<'SWIFT'
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 3,
      let processIdentifier = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data(
        "usage: window-id <pid> <selector> [main-width] [main-height]\n".utf8
    ))
    exit(2)
}

let selector = CommandLine.arguments[2]
let mainWidth = CommandLine.arguments.count >= 4 ? Double(CommandLine.arguments[3]) : nil
let mainHeight = CommandLine.arguments.count >= 5 ? Double(CommandLine.arguments[4]) : nil
guard let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] else {
    exit(1)
}

let candidates = windows.compactMap { window -> (
    number: UInt32,
    width: Double,
    height: Double,
    layer: Int,
    title: String
)? in
    guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processIdentifier,
          let windowNumber = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = (bounds["Width"] as? NSNumber)?.doubleValue,
          let height = (bounds["Height"] as? NSNumber)?.doubleValue,
          width >= 200,
          height >= 150 else {
        return nil
    }
    return (
        windowNumber,
        width,
        height,
        (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1,
        window[kCGWindowName as String] as? String ?? ""
    )
}

if selector == "__LIST__" {
    for candidate in candidates {
        print(
            "id=\(candidate.number) layer=\(candidate.layer) "
            + "title=\(String(reflecting: candidate.title)) "
            + "bounds=\(Int(candidate.width.rounded()))x\(Int(candidate.height.rounded()))"
        )
    }
    exit(0)
}

for candidate in candidates {
    let titleMatches: Bool
    if selector == "__QUICK_LOOK__" {
        titleMatches = candidate.layer >= 8
            && candidate.width >= 300
            && candidate.width <= 600
            && candidate.height >= 180
            && candidate.height <= 500
            && !candidate.title.isEmpty
            && mainWidth.map { candidate.width < $0 } != false
            && mainHeight.map { candidate.height < $0 } != false
            && !candidate.title.localizedCaseInsensitiveContains("ClipFlow Settings")
    } else {
        titleMatches = selector.isEmpty
            || candidate.title.localizedCaseInsensitiveContains(selector)
    }
    guard titleMatches else { continue }

    let titleToken = candidate.title.isEmpty
        ? "_"
        : Data(candidate.title.utf8).base64EncodedString()
    print(
        "\(candidate.number) \(Int(candidate.width.rounded())) "
        + "\(Int(candidate.height.rounded())) \(candidate.layer) \(titleToken)"
    )
    exit(0)
}

exit(1)
SWIFT

xcrun swiftc "$HELPER_SOURCE" -framework CoreGraphics -o "$HELPER_EXECUTABLE"

wait_for_ready_file() {
    local pid="$1"
    local ready_file="$2"
    local expected_token="$3"
    local actual_token=""

    for _ in {1..80}; do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "ClipFlowApp exited before confirming visual-acceptance isolation." >&2
            return 1
        fi
        if [[ -f "$ready_file" ]]; then
            actual_token="$(<"$ready_file")"
            if [[ "$actual_token" == "$expected_token" ]]; then
                return 0
            fi
            echo "Visual-acceptance ready token did not match the launched scenario." >&2
            return 1
        fi
        sleep 0.25
    done

    echo "Timed out waiting for the visual-acceptance ready file: $ready_file" >&2
    return 1
}

wait_for_window_info() {
    local pid="$1"
    local selector="$2"
    local main_width="$3"
    local main_height="$4"
    local window_info=""

    for _ in {1..80}; do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "ClipFlowApp exited before its capture window appeared." >&2
            return 1
        fi
        window_info="$(
            "$HELPER_EXECUTABLE" "$pid" "$selector" "$main_width" "$main_height" \
                2>/dev/null || true
        )"
        if [[ "$window_info" =~ ^[0-9]+\ [0-9]+\ [0-9]+\ -?[0-9]+\ [A-Za-z0-9+/=_-]+$ ]]; then
            printf '%s\n' "$window_info"
            return 0
        fi
        sleep 0.25
    done

    if [[ "$selector" == "__QUICK_LOOK__" ]]; then
        echo "Timed out waiting for a secondary Quick Look window owned by PID $pid." >&2
    elif [[ -n "$selector" ]]; then
        echo "Timed out waiting for a window owned by PID $pid with title containing '$selector'." >&2
    else
        echo "Timed out waiting for a visible window owned by PID $pid." >&2
    fi
    echo "Candidate windows for PID $pid:" >&2
    "$HELPER_EXECUTABLE" "$pid" "__LIST__" "$main_width" "$main_height" \
        2>&1 | sed 's/^/  /' >&2 || true
    return 1
}

decode_window_title() {
    local title_token="$1"
    if [[ "$title_token" == "_" ]]; then
        printf '%s\n' "<empty>"
    else
        printf '%s' "$title_token" | /usr/bin/base64 -D
        printf '\n'
    fi
}

capture_scenario() {
    local slug="$1"
    local language="$2"
    local locale="$3"
    local appearance="$4"
    local density="$5"
    local width="$6"
    local height="$7"
    local window_selector="$8"
    local validate_size="$9"
    shift 9
    local data_directory="$RUN_ROOT/data-$slug"
    local fixture_file="$data_directory/ClipFlow Demo File.txt"
    local ready_file="$data_directory/.visual-acceptance-ready"
    local output_file="$OUTPUT_DIR/$slug.png"
    local temporary_output="$output_file.tmp.png"
    local acceptance_token=""
    local window_id=""
    local actual_width=""
    local actual_height=""
    local window_layer=""
    local window_title_token=""
    local window_title=""

    SCENARIO_INDEX=$((SCENARIO_INDEX + 1))
    acceptance_token="clipflow-$slug-$$-$SCENARIO_INDEX"
    mkdir -p "$data_directory"
    printf '%s\n' "ClipFlow Finder thumbnail fixture" >"$fixture_file"
    rm -f "$ready_file" "$output_file" "$temporary_output"

    local -a environment=(
        "CLIPFLOW_VISUAL_ACCEPTANCE=1"
        "CLIPFLOW_ACCEPTANCE_TOKEN=$acceptance_token"
        "CLIPFLOW_SEED_DEMO=1"
        "CLIPFLOW_DEVELOPMENT_DATA_DIR=$data_directory"
        "CLIPFLOW_DEMO_FILE_URL=$fixture_file"
        "CLIPFLOW_DEMO_NOW=1700000000"
        "CLIPFLOW_WINDOW_WIDTH=$width"
        "CLIPFLOW_WINDOW_HEIGHT=$height"
        "CLIPFLOW_APPEARANCE_MODE=$appearance"
        "CLIPFLOW_LIST_DENSITY=$density"
        "CLIPFLOW_LOCALE_IDENTIFIER=$language"
        "CLIPFLOW_BROWSER_ENABLED=1"
        "AppleLanguages=($language)"
        "AppleLocale=$locale"
        "AppleInterfaceStyle=$([[ "$appearance" == "dark" ]] && echo Dark || echo Light)"
    )
    if (($# > 0)); then
        environment+=("$@")
    fi

    env "${environment[@]}" "$APP_EXECUTABLE" &
    LAUNCHED_PID=$!

    wait_for_ready_file "$LAUNCHED_PID" "$ready_file" "$acceptance_token"
    read -r window_id actual_width actual_height window_layer window_title_token <<< \
        "$(wait_for_window_info "$LAUNCHED_PID" "$window_selector" "$width" "$height")"
    window_title="$(decode_window_title "$window_title_token")"
    if [[ "$validate_size" == "1" ]] \
        && ((actual_width != width || actual_height != height)); then
        echo "Scenario '$slug' requested ${width}x${height}, but ClipFlow opened ${actual_width}x${actual_height}." >&2
        return 1
    fi
    sleep 1

    if [[ "$window_selector" == "__QUICK_LOOK__" ]]; then
        local verified_info=""
        local verified_id=""
        local verified_width=""
        local verified_height=""
        local verified_layer=""
        local verified_title_token=""
        verified_info="$(
            "$HELPER_EXECUTABLE" "$LAUNCHED_PID" "$window_selector" "$width" "$height" \
                2>/dev/null || true
        )"
        read -r verified_id verified_width verified_height verified_layer verified_title_token <<< \
            "$verified_info"
        if [[ "$verified_id" != "$window_id" \
            || "$verified_width" != "$actual_width" \
            || "$verified_height" != "$actual_height" \
            || "$verified_layer" != "$window_layer" \
            || "$verified_title_token" != "$window_title_token" \
            || "$window_layer" -lt 8 \
            || "$window_title" == *"ClipFlow Settings"* ]]; then
            echo "Quick Look window changed or failed validation before capture." >&2
            echo "Initial: id=$window_id layer=$window_layer title=$window_title bounds=${actual_width}x${actual_height}" >&2
            echo "Current: $verified_info" >&2
            return 1
        fi
    fi

    /usr/sbin/screencapture -x -l "$window_id" "$temporary_output"

    if [[ ! -s "$temporary_output" ]]; then
        echo "Capture for '$slug' did not produce a nonempty PNG." >&2
        return 1
    fi
    mv "$temporary_output" "$output_file"
    echo "Captured $output_file (PID $LAUNCHED_PID, window $window_id, layer $window_layer, title '$window_title', ${actual_width}x${actual_height})"
    cleanup_launched_process
}

capture_scenario \
    "dark-zh-wide" "zh-Hans" "zh_CN" "dark" "comfortable" 1000 680 "" 1
capture_scenario \
    "light-en-wide" "en" "en_US" "light" "comfortable" 1000 680 "" 1
capture_scenario \
    "light-en-compact" "en" "en_US" "light" "compact" 800 520 "" 1
capture_scenario \
    "light-en-settings" "en" "en_US" "light" "comfortable" 1000 680 "ClipFlow Settings" 0 \
    "CLIPFLOW_SHOW_SETTINGS=1"
capture_scenario \
    "dark-zh-settings" "zh-Hans" "zh_CN" "dark" "comfortable" 1000 680 "ClipFlow 设置" 0 \
    "CLIPFLOW_SHOW_SETTINGS=1"
capture_scenario \
    "light-en-file-actions" "en" "en_US" "light" "comfortable" 1000 680 "" 1 \
    "CLIPFLOW_SELECTED_KIND=file"
capture_scenario \
    "light-en-link-actions" "en" "en_US" "light" "comfortable" 1000 680 "" 1 \
    "CLIPFLOW_SELECTED_KIND=link"
capture_scenario \
    "light-en-image-actions" "en" "en_US" "light" "comfortable" 1000 680 "" 1 \
    "CLIPFLOW_SELECTED_KIND=image"
capture_scenario \
    "light-en-text-actions" "en" "en_US" "light" "comfortable" 1000 680 "" 1 \
    "CLIPFLOW_SELECTED_KIND=text"
capture_scenario \
    "light-en-browser-empty" "en" "en_US" "light" "comfortable" 1000 680 "" 1 \
    "CLIPFLOW_SHOW_BROWSER_TABS=1" \
    "CLIPFLOW_BROWSER_EMPTY=1"
capture_scenario \
    "light-en-quick-look" "en" "en_US" "light" "comfortable" 1000 680 "__QUICK_LOOK__" 0 \
    "CLIPFLOW_SHOW_PREVIEW=1"

echo "Visual-acceptance captures are in $OUTPUT_DIR"
