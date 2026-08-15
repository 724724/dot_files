#!/bin/sh

addr="$1"
[ -n "$addr" ] || exit 1

info=$(hyprctl clients -j 2>/dev/null | jq -r --arg address "$addr" \
    '.[] | select(.address == $address) | [.at[0], .at[1], .size[0], .size[1]] | @tsv')
selector="address:$addr"

if [ -z "$info" ] || [ "$info" = "null" ]; then
    exec hyprctl eval "hl.dispatch(hl.dsp.focus({ window = \"$selector\" })); hl.dispatch(hl.dsp.window.bring_to_top(\"$selector\"))"
fi

set -- $info
x=$1
y=$2
width=$3
height=$4
center_x=$((x + width / 2))
center_y=$((y + height / 2))

hyprctl eval "hl.dispatch(hl.dsp.cursor.move({ x = $center_x, y = $center_y })); hl.dispatch(hl.dsp.focus({ window = \"$selector\" })); hl.dispatch(hl.dsp.window.bring_to_top(\"$selector\"))" >/dev/null
