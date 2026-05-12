#!/bin/bash
# Usage: brightness-osd.sh raise | lower | +2 | -2
#
# Brightness control with integrated DPMS:
#   - Lowering past 0% silently turns the display off (no OSD).
#   - Pressing any brightness key while DPMS is off wakes the display
#     and applies the keypress normally (so 0% + raise → 5%).

DPMS=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].dpmsStatus')
[ "$DPMS" = "false" ] && hyprctl dispatch dpms on

case "$1" in
    raise)  brightnessctl set +5%   >/dev/null ;;
    lower)  brightnessctl set 5%-   >/dev/null ;;
    +*)     brightnessctl set "${1:1}%+" >/dev/null ;;
    -*)     brightnessctl set "${1:1}%-" >/dev/null ;;
esac

MAX=$(brightnessctl max)
CUR=$(brightnessctl get)
PCT=$((CUR * 100 / MAX))

if [ "$PCT" -le 0 ]; then
    hyprctl dispatch dpms off
else
    qs ipc -c desktop call osd brightness "$PCT"
fi
