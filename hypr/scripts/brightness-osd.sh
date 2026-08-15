#!/bin/bash
# Usage: brightness-osd.sh raise | lower | +2 | -2
#
# Acceleration:
#   - Single press / slow tapping → 1% steps (precise)
#   - Holding → step grows: 1 → 2 → 3 → ... → 15 (capped)
#   - Direction/mode change → streak resets
#   - Pause > 700ms → streak resets

RAMP_STATE="/tmp/brightness-ramp.state"
DPMS_STATE="/tmp/brightness-dpms.state"

NOW=$EPOCHREALTIME
NOW_MS=$(( ${NOW%.*} * 1000 + 10#${NOW#*.} / 1000 ))

# ── Streak (방향 변경 시 리셋) ────────────────────────────────────────────
LAST_MS=0; STREAK=0; LAST_ACTION=""
if [ -s "$RAMP_STATE" ]; then
    read -r LAST_MS STREAK LAST_ACTION < "$RAMP_STATE"
    [[ "$LAST_MS" =~ ^[0-9]+$ ]] || LAST_MS=0
    [[ "$STREAK" =~ ^[0-9]+$ ]] || STREAK=0
fi
DELTA=$((NOW_MS - LAST_MS))

if [ "$1" != "$LAST_ACTION" ]; then
    STREAK=1
elif [ "$DELTA" -lt 700 ]; then
    STREAK=$((STREAK + 1))
else
    STREAK=1
fi

printf '%s %s %s\n' "$NOW_MS" "$STREAK" "$1" > "$RAMP_STATE"

STEP=$(( 1 + STREAK / 2 ))
[ "$STEP" -gt 15 ] && STEP=15

# ── DPMS wake ─────────────────────────────────────────────────────────────
DPMS=""
[[ -r "$DPMS_STATE" ]] && IFS= read -r DPMS < "$DPMS_STATE"
if [ "$DPMS" = "off" ]; then
    hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null 2>&1
    printf 'on\n' > "$DPMS_STATE"
fi

# ── Apply ─────────────────────────────────────────────────────────────────
case "$1" in
    raise)  brightnessctl set "+${STEP}%" >/dev/null ;;
    lower)  brightnessctl set "${STEP}%-" >/dev/null ;;
    +*)     brightnessctl set "${1:1}%+" >/dev/null ;;
    -*)     brightnessctl set "${1:1}%-" >/dev/null ;;
esac

CUR=$(< /sys/class/backlight/intel_backlight/brightness)
MAX=$(< /sys/class/backlight/intel_backlight/max_brightness)
PCT=$((CUR * 100 / MAX))

if [ "$PCT" -le 0 ]; then
    hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })' >/dev/null 2>&1
    printf 'off\n' > "$DPMS_STATE"
else
    qs ipc -c desktop call osd brightness "$PCT" 2>/dev/null &
    disown
fi

# Persist for restore on next boot
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
[[ -d "$STATE_DIR" ]] || mkdir -p "$STATE_DIR"
umask 022
printf '%s\n' "$PCT" > "$STATE_DIR/brightness"
