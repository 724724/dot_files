#!/usr/bin/env bash
# Usage: capture-thumbs.sh <wmClass>
# Captures thumbnails of all windows of the given class and outputs JSON.
WC="${1,,}"   # lowercase

CLIENTS=$(hyprctl clients -j 2>/dev/null | jq \
    --arg cls "$WC" \
    '[.[] | select((.class | ascii_downcase) == $cls) |
      {address, title, at, size}]' 2>/dev/null)

[ -z "$CLIENTS" ] || [ "$CLIENTS" = "null" ] && echo "[]" && exit 0

# Screenshot each window region
printf '%s' "$CLIENTS" | jq -r '.[] | [.address, .at[0], .at[1], .size[0], .size[1]] | @tsv' |
while IFS=$'\t' read -r ADDR X Y W H; do
    CLEAN=${ADDR#0x}
    [ "$W" -gt 0 ] && [ "$H" -gt 0 ] && \
        grim -g "${X},${Y} ${W}x${H}" "/tmp/qs-dock-${CLEAN}.png" 2>/dev/null || true
done

# Output with thumb paths
printf '%s' "$CLIENTS" | jq -c \
    '[.[] | . + {thumbPath: ("/tmp/qs-dock-" + (.address | ltrimstr("0x")) + ".png")}]'
