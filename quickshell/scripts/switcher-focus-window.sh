#!/bin/sh

addr="$1"
[ -n "$addr" ] || exit 1

info=$(hyprctl clients -j 2>/dev/null | jq -c --arg address "$addr" '.[] | select(.address == $address) | {at, size}')
selector="address:$addr"

if [ -z "$info" ] || [ "$info" = "null" ]; then
    exec hyprctl eval "hl.dispatch(hl.dsp.focus({ window = \"$selector\" })); hl.dispatch(hl.dsp.window.bring_to_top(\"$selector\"))"
fi

x=$(printf '%s' "$info" | jq -r '.at[0]')
y=$(printf '%s' "$info" | jq -r '.at[1]')
width=$(printf '%s' "$info" | jq -r '.size[0]')
height=$(printf '%s' "$info" | jq -r '.size[1]')
center_x=$((x + width / 2))
center_y=$((y + height / 2))

hyprctl eval "hl.dispatch(hl.dsp.cursor.move({ x = $center_x, y = $center_y })); hl.dispatch(hl.dsp.focus({ window = \"$selector\" })); hl.dispatch(hl.dsp.window.bring_to_top(\"$selector\"))" >/dev/null
