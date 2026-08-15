#!/usr/bin/env bash

# Fixed-argument screenshot / recording backend for desktop/capture.
# The Quickshell UI owns all interaction; this script only validates the
# selected target and talks to grim, ImageMagick and GPU Screen Recorder.

set -u
umask 077

ACTION="${1:-}"
MODE="${2:-}"
OUTPUT_NAME="${3:-}"
POS_X="${4:-0}"
POS_Y="${5:-0}"
SIZE_W="${6:-0}"
SIZE_H="${7:-0}"
SHOW_CURSOR="${8:-0}"
SAVE_MODE="${9:-documents}"
MICROPHONE="${10:-0}"
DESKTOP_AUDIO="${11:-1}"
RECORD_PATH="${12:-}"
WINDOW_ADDRESS="${13:-}"

die() {
    printf 'capture-tool: %s\n' "$1" >&2
    exit "${2:-2}"
}

valid_output() {
    [[ "$OUTPUT_NAME" =~ ^[A-Za-z0-9._-]{1,64}$ ]]
}

valid_integer() {
    [[ "$1" =~ ^-?[0-9]{1,7}$ ]]
}

valid_dimension() {
    [[ "$1" =~ ^[0-9]{1,7}$ ]] && (( 10#$1 >= 2 ))
}

valid_window_address() {
    [[ "$1" =~ ^0x[0-9A-Fa-f]{1,16}$ ]]
}

focus_window_address() {
    local address="$1"
    valid_window_address "$address" || return 1

    # This Hyprland configuration uses the Lua dispatcher API. The legacy
    # `dispatch focuswindow address:...` form is parsed as Lua here and fails
    # before the selected window can be raised.
    /usr/bin/hyprctl eval \
        "hl.dispatch(hl.dsp.focus({ window = \"address:$address\" })); hl.dispatch(hl.dsp.window.bring_to_top({ window = \"address:$address\" }))"
}

desktop_directory() {
    local queried=""
    if command -v xdg-user-dir >/dev/null 2>&1; then
        queried="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
    fi
    [[ -n "$queried" && "$queried" == /* ]] && printf '%s\n' "$queried" || printf '%s\n' "$HOME/Desktop"
}

documents_directory() {
    local queried=""
    if command -v xdg-user-dir >/dev/null 2>&1; then
        queried="$(xdg-user-dir DOCUMENTS 2>/dev/null || true)"
    fi
    [[ -n "$queried" && "$queried" == /* ]] && printf '%s\n' "$queried" || printf '%s\n' "$HOME/Documents"
}

recorder_health() {
    RECORDER_PATH="$(command -v gpu-screen-recorder 2>/dev/null || true)"
    RECORDER_PROBLEM=""
    if [[ -z "$RECORDER_PATH" ]]; then
        RECORDER_PROBLEM="not-installed"
        return 1
    fi

    # A command can exist while being impossible to start after an unsupported
    # partial Arch upgrade. Diagnose the trusted installed binary without
    # executing it so the QML never advertises a broken recorder as available.
    local loader_output=""
    loader_output="$(/usr/bin/ldd "$RECORDER_PATH" 2>&1 || true)"
    if [[ "$loader_output" == *"not found"* ]]; then
        RECORDER_PROBLEM="missing-shared-library"
        return 1
    fi
    return 0
}

notify_recorder_problem() {
    if [[ "${RECORDER_PROBLEM:-}" == "missing-shared-library" ]]; then
        /usr/bin/notify-send -a "Screenshot" -u normal \
            "System update required" \
            "Run sudo pacman -Syu, reboot, then try recording again." >/dev/null 2>&1 || true
    else
        /usr/bin/notify-send -a "Screenshot" -u normal \
            "Screen recording is unavailable" \
            "Install it with: sudo pacman -Syu --needed gpu-screen-recorder" >/dev/null 2>&1 || true
    fi
}

if [[ "$ACTION" == "check" ]]; then
    RECORDER_PATH=""
    RECORDER_PROBLEM=""
    if recorder_health; then
        printf '{"recorder":true,"backend":"gpu-screen-recorder","problem":""}\n'
    else
        printf '{"recorder":false,"backend":"gpu-screen-recorder","problem":"%s"}\n' \
            "$RECORDER_PROBLEM"
    fi
    exit 0
fi

case "$MODE" in
    screen|window|portion) ;;
    *) die "invalid capture mode" ;;
esac

valid_output || die "invalid output name"
valid_integer "$POS_X" || die "invalid x coordinate"
valid_integer "$POS_Y" || die "invalid y coordinate"
valid_dimension "$SIZE_W" || [[ "$MODE" == "screen" ]] || die "invalid width"
valid_dimension "$SIZE_H" || [[ "$MODE" == "screen" ]] || die "invalid height"
[[ "$MODE" != "window" ]] || valid_window_address "$WINDOW_ADDRESS" \
    || die "invalid window address"
[[ "$SHOW_CURSOR" == "0" || "$SHOW_CURSOR" == "1" ]] || die "invalid cursor option"
[[ "$MICROPHONE" == "0" || "$MICROPHONE" == "1" ]] || die "invalid microphone option"
[[ "$DESKTOP_AUDIO" == "0" || "$DESKTOP_AUDIO" == "1" ]] || die "invalid audio option"
case "$SAVE_MODE" in
    desktop|documents|clipboard|custom) ;;
    *) die "invalid save destination" ;;
esac

if [[ "$ACTION" == "screenshot" ]]; then
    command -v grim >/dev/null 2>&1 || die "grim is not installed" 127
    command -v wl-copy >/dev/null 2>&1 || die "wl-clipboard is not installed" 127

    runtime_root="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-capture"
    /usr/bin/mkdir -p -m 700 "$runtime_root" || die "could not create runtime directory"
    raw_path="$runtime_root/raw-$$.png"
    final_temp="$runtime_root/final-$$.png"

    cleanup_capture() {
        /usr/bin/rm -f -- "$raw_path" "$final_temp"
    }
    trap cleanup_capture EXIT

    if [[ "$MODE" == "window" ]]; then
        command -v hyprctl >/dev/null 2>&1 || die "hyprctl is not installed" 127
        command -v jq >/dev/null 2>&1 || die "jq is not installed" 127
        active_json="$(/usr/bin/hyprctl activewindow -j 2>/dev/null || true)"
        active_address="$(/usr/bin/jq -r '.address // empty' <<<"$active_json" 2>/dev/null || true)"
        if [[ "$active_address" != "$WINDOW_ADDRESS" ]]; then
            focus_window_address "$WINDOW_ADDRESS" >/dev/null 2>&1 \
                || die "selected window is no longer available" 1
            # Wait for the compositor to commit the raised window before grim
            # copies the selected geometry.
            /usr/bin/sleep 0.10
        fi
    fi

    grim_args=()
    [[ "$SHOW_CURSOR" == "1" ]] && grim_args+=("-c")
    if [[ "$MODE" == "screen" ]]; then
        grim_args+=("-o" "$OUTPUT_NAME")
    else
        grim_args+=("-g" "${POS_X},${POS_Y} ${SIZE_W}x${SIZE_H}")
    fi
    grim_args+=("$raw_path")
    /usr/bin/grim "${grim_args[@]}" || die "screen capture failed" 1

    if [[ "$MODE" == "window" ]]; then
        command -v magick >/dev/null 2>&1 || die "ImageMagick is not installed" 127
        # Preserve the captured window exactly, then grow only a transparent
        # canvas around it. The shadow is composited into that alpha padding;
        # unlike the old winshot flow, regular region shots never get a shadow.
        /usr/bin/magick "$raw_path" \
            \( +clone -background black -shadow 48x18+0+12 \) \
            +swap -background none -layers merge +repage \
            -alpha set -strip -define png:compression-level=3 "$final_temp" \
            || die "window shadow composition failed" 1
    else
        /usr/bin/mv -f -- "$raw_path" "$final_temp" || die "could not prepare screenshot"
    fi

    if [[ "$SAVE_MODE" == "clipboard" ]]; then
        /usr/bin/wl-copy --type image/png < "$final_temp" || die "clipboard copy failed" 1
        /usr/bin/notify-send -a "Screenshot" -i camera-photo-symbolic \
            "Screenshot copied" "The image is ready to paste." >/dev/null 2>&1 || true
        exit 0
    fi

    if [[ "$SAVE_MODE" == "desktop" ]]; then
        save_dir="$(desktop_directory)"
    elif [[ "$SAVE_MODE" == "documents" ]]; then
        save_dir="$(documents_directory)"
    elif [[ "$SAVE_MODE" == "custom" ]]; then
        [[ "$RECORD_PATH" == /* && "$RECORD_PATH" != *$'\n'* && "$RECORD_PATH" != *$'\r'* \
            && -d "$RECORD_PATH" ]] || die "invalid custom screenshot directory"
        save_dir="$RECORD_PATH"
    else
        die "invalid screenshot destination"
    fi
    /usr/bin/mkdir -p -- "$save_dir" || die "could not create screenshot directory"
    filename="Screenshot $(/usr/bin/date '+%Y-%m-%d at %H.%M.%S').png"
    final_path="$save_dir/$filename"
    # Every file-backed screenshot is also copied. Clipboard mode above is the
    # only destination that deliberately skips writing a file.
    /usr/bin/wl-copy --type image/png < "$final_temp" || die "clipboard copy failed" 1
    /usr/bin/mv -f -- "$final_temp" "$final_path" || die "could not save screenshot"

    (
        action="$(/usr/bin/notify-send -a "Screenshot" -i "$final_path" \
            "Screenshot saved" "$filename" --action="open=Show in Files" --wait 2>/dev/null || true)"
        if [[ "$action" == "open" ]] && command -v nautilus >/dev/null 2>&1; then
            /usr/bin/setsid -f /usr/bin/nautilus --select "$final_path" >/dev/null 2>&1
        fi
    ) &
    exit 0
fi

if [[ "$ACTION" == "record" ]]; then
    RECORDER_PATH=""
    RECORDER_PROBLEM=""
    recorder_health || {
        notify_recorder_problem
        exit 127
    }
    [[ "$RECORD_PATH" == /* && "$RECORD_PATH" == *.mkv ]] || die "invalid recording path"
    record_dir="${RECORD_PATH%/*}"
    [[ -n "$record_dir" && "$record_dir" != "$RECORD_PATH" ]] || die "invalid recording directory"
    /usr/bin/mkdir -p -- "$record_dir" || die "could not create recording directory"

    cursor_value="no"
    [[ "$SHOW_CURSOR" == "1" ]] && cursor_value="yes"
    recorder_args=("-f" "60" "-fm" "vfr" "-k" "h264" "-q" "high"
        "-cursor" "$cursor_value")
    if [[ "$MODE" == "screen" ]]; then
        recorder_args=("-w" "$OUTPUT_NAME" "${recorder_args[@]}")
    else
        # %+d emits either +N or -N, so monitors placed left/above the primary
        # remain valid instead of producing the invalid "+-N" form.
        printf -v record_region '%sx%s%+d%+d' "$SIZE_W" "$SIZE_H" "$POS_X" "$POS_Y"
        # GPU Screen Recorder 6 accepts the geometry directly as the capture
        # source. Its older `-w region -region ...` spelling is deprecated.
        recorder_args=("-w" "$record_region" "${recorder_args[@]}")
    fi

    if [[ "$DESKTOP_AUDIO" == "1" && "$MICROPHONE" == "1" ]]; then
        recorder_args+=("-a" "default_output|default_input")
    elif [[ "$DESKTOP_AUDIO" == "1" ]]; then
        recorder_args+=("-a" "default_output")
    elif [[ "$MICROPHONE" == "1" ]]; then
        recorder_args+=("-a" "default_input")
    fi
    recorder_args+=("-o" "$RECORD_PATH")
    exec "$RECORDER_PATH" "${recorder_args[@]}"
fi

die "invalid action"
