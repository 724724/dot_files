#!/usr/bin/env bash
# Finish the private pre-lock capture after the QML process has already begun
# acquiring ext-session-lock. Only blurred output files are published through
# manifest.json; raw screen contents are never referenced by QML.

set -uo pipefail

readonly OUTPUT_ROOT="${1:-}"
readonly EXPECTED_ROOT="/run/user/$(id -u)/quickshell-lock"

if [[ "$OUTPUT_ROOT" != "$EXPECTED_ROOT" ]]; then
    exit 0
fi

readonly SNAPSHOT_DIR="$OUTPUT_ROOT/snapshot"
readonly CAPTURE_PLAN="$SNAPSHOT_DIR/capture-plan.json"
readonly MANIFEST="$SNAPSHOT_DIR/manifest.json"

log_failure() {
    /usr/bin/logger -t quickshell-lock-capture -- "$1" 2>/dev/null || true
}

[[ -r "$CAPTURE_PLAN" && -r "$MANIFEST" ]] || exit 0

# A crash restart preserves the completed generation. Never blur twice.
if /usr/bin/jq -e '.version == 1 and (.outputs | length) > 0' \
        "$MANIFEST" >/dev/null 2>&1; then
    exit 0
fi

declare -a output_names=()
declare -a output_files=()
declare -a blur_pids=()

while IFS=$'\t' read -r output_name raw_name filename; do
    [[ "$output_name" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || continue
    [[ "$raw_name" =~ ^\.output-[0-9]+\.raw\.jpg$ ]] || continue
    [[ "$filename" =~ ^output-[0-9]+\.jpg$ ]] || continue
    [[ -s "$SNAPSHOT_DIR/$raw_name" ]] || continue

    output_names+=("$output_name")
    output_files+=("$filename")
    temporary="$SNAPSHOT_DIR/.$filename"

    (
        if /usr/bin/timeout --foreground --kill-after=0.15s 2.00s \
                /usr/bin/magick "$SNAPSHOT_DIR/$raw_name" \
                    -blur 0x24 -strip -sampling-factor 4:2:0 \
                    -quality 86 "$temporary" 2>/dev/null; then
            /usr/bin/chmod 0600 -- "$temporary" 2>/dev/null || true
            /usr/bin/mv -f -- "$temporary" "$SNAPSHOT_DIR/$filename"
        else
            log_failure "deferred CPU blur failed for output $output_name; using wallpaper fallback for that output"
            /usr/bin/unlink "$temporary" 2>/dev/null || true
        fi
    ) &
    blur_pids+=("$!")
done < <(
    /usr/bin/jq -r '.outputs[] | [.name, .raw, .file] | @tsv' \
        "$CAPTURE_PLAN" 2>/dev/null
)

for blur_pid in "${blur_pids[@]}"; do
    wait "$blur_pid" 2>/dev/null || true
done

manifest_tmp="$SNAPSHOT_DIR/.manifest.$$.json"
first=true
{
    printf '{"version":1,"outputs":['
    for index in "${!output_names[@]}"; do
        [[ -s "$SNAPSHOT_DIR/${output_files[$index]}" ]] || continue
        if [[ "$first" == true ]]; then
            first=false
        else
            printf ','
        fi
        printf '{"name":"%s","file":"%s"}' \
            "${output_names[$index]}" "${output_files[$index]}"
    done
    printf ']}\n'
} > "$manifest_tmp" 2>/dev/null || exit 0

/usr/bin/chmod 0600 -- "$manifest_tmp" 2>/dev/null || true
/usr/bin/mv -f -- "$manifest_tmp" "$MANIFEST" 2>/dev/null || true

# Raw frames have served their only purpose and should not outlive the blur.
/usr/bin/find "$SNAPSHOT_DIR" -mindepth 1 -maxdepth 1 -type f \
    -name '.output-*.raw.jpg' -delete 2>/dev/null || true
/usr/bin/unlink "$CAPTURE_PLAN" 2>/dev/null || true
exit 0
