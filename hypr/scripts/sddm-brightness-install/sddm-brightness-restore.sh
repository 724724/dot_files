#!/bin/bash
# Restore brightness at boot, before SDDM greeter draws.
# Reads /home/sejunlee/.local/state/brightness (saved by brightness-osd.sh).

USER_HOME="/home/sejunlee"
STATE_FILE="$USER_HOME/.local/state/brightness"
BL_DIR="/sys/class/backlight/intel_backlight"

[ -r "$STATE_FILE" ] || exit 0
[ -w "$BL_DIR/brightness" ] || exit 0

PCT=$(tr -dc '0-9' < "$STATE_FILE")
[ -n "$PCT" ] || exit 0
[ "$PCT" -ge 1 ] && [ "$PCT" -le 100 ] || exit 0

MAX=$(cat "$BL_DIR/max_brightness")
VAL=$((MAX * PCT / 100))
[ "$VAL" -lt 1 ] && VAL=1
echo "$VAL" > "$BL_DIR/brightness"
