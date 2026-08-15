#!/usr/bin/env bash
# Capture a moderately downscaled image of each active output immediately
# before the session-lock client starts. systemd owns the destination runtime
# directory and removes it after a final stop/authenticated unlock.

set -uo pipefail

readonly OUTPUT_ROOT="${1:-}"
readonly EXPECTED_ROOT="/run/user/$(id -u)/quickshell-lock"

# Never write or delete through a caller-controlled broad path. The unit passes
# exactly %t/quickshell-lock, which resolves to this per-user runtime directory.
if [[ "$OUTPUT_ROOT" != "$EXPECTED_ROOT" ]]; then
    exit 0
fi

readonly SNAPSHOT_DIR="$OUTPUT_ROOT/snapshot"
readonly ATTEMPT_MARKER="$OUTPUT_ROOT/capture-attempted"
readonly MANIFEST="$SNAPSHOT_DIR/manifest.json"
readonly CAPTURE_PLAN="$SNAPSHOT_DIR/capture-plan.json"
readonly OUTPUT_HINT="/run/user/$(id -u)/quickshell-desktop-outputs.json"

log_failure() {
    /usr/bin/logger -t quickshell-lock-capture -- "$1" 2>/dev/null || true
}

umask 077
/usr/bin/install -d -m 0700 -- "$SNAPSHOT_DIR" 2>/dev/null || exit 0

# Automatic service recovery happens while the compositor is already locked.
# Mark the first attempt before any capture work so a crash or timeout cannot
# make a restart photograph the lock surface (or whatever lies below it).
if [[ -e "$ATTEMPT_MARKER" ]]; then
    exit 0
fi
: > "$ATTEMPT_MARKER" 2>/dev/null || exit 0
/usr/bin/chmod 0600 -- "$ATTEMPT_MARKER" 2>/dev/null || true

# Remove only incomplete files inside the exact validated runtime directory.
/usr/bin/find "$SNAPSHOT_DIR" -mindepth 1 -maxdepth 1 -type f \
    \( -name 'output-*.jpg' -o -name '.output-*.jpg' -o -name 'capture-plan.json' \
       -o -name '.manifest.*.json' -o -name 'manifest.json' \) \
    -delete 2>/dev/null || true

output_names_json=""
if [[ -r "$OUTPUT_HINT" ]]; then
    output_names_json="$(/usr/bin/head -c 4096 -- "$OUTPUT_HINT" 2>/dev/null)" || output_names_json=""
fi

if ! /usr/bin/jq -e 'type == "array"' <<< "$output_names_json" >/dev/null 2>&1; then
    output_names_json="$(
        /usr/bin/timeout --foreground --kill-after=0.10s 0.75s \
            /usr/bin/qs -c desktop ipc call lockCapture outputs 2>/dev/null
    )" || output_names_json=""
fi

if ! /usr/bin/jq -e 'type == "array"' <<< "$output_names_json" >/dev/null 2>&1; then
    monitors_json="$(
        /usr/bin/timeout --foreground --kill-after=0.10s 1.50s \
            /usr/bin/hyprctl -j monitors 2>/dev/null
    )" || {
        log_failure "could not query active outputs from desktop or Hyprland; using wallpaper fallback"
        exit 0
    }
    output_names_json="$(
        /usr/bin/jq -c '[.[] | select((.disabled // false) == false) | .name]' \
            <<< "$monitors_json" 2>/dev/null
    )" || output_names_json="[]"
fi

declare -a output_names=()
declare -a output_files=()
declare -a capture_pids=()

while IFS= read -r output_name; do
    # DRM connector names fit this grammar. Reject anything that could affect a
    # path or the hand-written JSON manifest instead of trying to escape it.
    [[ "$output_name" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || continue

    index="${#output_names[@]}"
    filename="output-${index}.jpg"
    raw="$SNAPSHOT_DIR/.output-${index}.raw.jpg"

    output_names+=("$output_name")
    output_files+=("$filename")

    (
        if /usr/bin/timeout --foreground --kill-after=0.15s 1.50s \
                /usr/bin/grim -o "$output_name" -s 0.25 \
                -t jpeg -q 90 "$raw" 2>/dev/null; then
            /usr/bin/chmod 0600 -- "$raw" 2>/dev/null || true
        else
            log_failure "capture failed for output $output_name; using wallpaper fallback for that output"
            /usr/bin/unlink "$raw" 2>/dev/null || true
        fi
    ) &
    capture_pids+=("$!")
done < <(
    /usr/bin/jq -r '.[]' <<< "$output_names_json" 2>/dev/null
)

if ((${#output_names[@]} == 0)); then
    log_failure "Hyprland returned no active outputs; using wallpaper fallback"
fi

# Captures run in parallel, so the critical pre-lock budget remains bounded by
# one output timeout instead of growing with the monitor count. Expensive CPU
# blur is deliberately deferred to ExecStartPost and overlaps QML startup.
for capture_pid in "${capture_pids[@]}"; do
    wait "$capture_pid" 2>/dev/null || true
done

plan_tmp="$SNAPSHOT_DIR/.capture-plan.$$.json"
first=true
{
    printf '{"version":1,"outputs":['
    for index in "${!output_names[@]}"; do
        [[ -s "$SNAPSHOT_DIR/.output-${index}.raw.jpg" ]] || continue
        if [[ "$first" == true ]]; then
            first=false
        else
            printf ','
        fi
        printf '{"name":"%s","raw":".output-%s.raw.jpg","file":"%s"}' \
            "${output_names[$index]}" "$index" "${output_files[$index]}"
    done
    printf ']}\n'
} > "$plan_tmp" 2>/dev/null || exit 0

/usr/bin/chmod 0600 -- "$plan_tmp" 2>/dev/null || true
/usr/bin/mv -f -- "$plan_tmp" "$CAPTURE_PLAN" 2>/dev/null || exit 0

# Keep an existing file in place before QML starts so FileView can watch the
# atomic replacement produced by the deferred blur helper.
manifest_tmp="$SNAPSHOT_DIR/.manifest.$$.json"
printf '{"version":1,"outputs":[]}\n' > "$manifest_tmp" 2>/dev/null || exit 0
/usr/bin/chmod 0600 -- "$manifest_tmp" 2>/dev/null || true
/usr/bin/mv -f -- "$manifest_tmp" "$MANIFEST" 2>/dev/null || true
exit 0
