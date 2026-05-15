#!/bin/bash
# Usage: focus-window.sh <hyprland-address>
#
# Focuses a window by address AND moves the cursor onto its center, so that
# Hyprland's `follow_mouse = 1` doesn't immediately steal focus back to whatever
# window happens to be under the cursor right after the focus change.
# This is the fix for "Super+Tab moves cursor but focus doesn't apply until I
# wiggle the mouse" — caused by cursor still hovering an unrelated surface.

ADDR="$1"
[ -z "$ADDR" ] && exit 1

INFO=$(hyprctl clients -j 2>/dev/null \
    | jq -c --arg a "$ADDR" '.[] | select(.address==$a) | {at, size}')

if [ -z "$INFO" ] || [ "$INFO" = "null" ]; then
    # Window not found — fall back to a plain focus dispatch.
    exec hyprctl dispatch "hl.dsp.focus({ window = \"address:$ADDR\" })"
fi

X=$(echo "$INFO" | jq -r '.at[0]')
Y=$(echo "$INFO" | jq -r '.at[1]')
W=$(echo "$INFO" | jq -r '.size[0]')
H=$(echo "$INFO" | jq -r '.size[1]')

CX=$((X + W / 2))
CY=$((Y + H / 2))

# Single eval so the focus + cursor move land on the same frame —
# avoids any visible flicker or ordering races with `follow_mouse`.
hyprctl eval "hl.dispatch(hl.dsp.focus({ window = \"address:$ADDR\" })); hl.dispatch(hl.dsp.cursor.move({ x = $CX, y = $CY }))" >/dev/null
