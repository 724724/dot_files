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
echo "$CLIENTS" | jq -c '.[]' | while IFS= read -r win; do
    ADDR=$(echo "$win" | jq -r '.address')
    CLEAN=$(echo "$ADDR" | sed 's/^0x//')
    X=$(echo "$win" | jq -r '.at[0]')
    Y=$(echo "$win" | jq -r '.at[1]')
    W=$(echo "$win" | jq -r '.size[0]')
    H=$(echo "$win" | jq -r '.size[1]')
    [ "$W" -gt 0 ] && [ "$H" -gt 0 ] && \
        grim -g "${X},${Y} ${W}x${H}" "/tmp/qs-dock-${CLEAN}.png" 2>/dev/null || true
done

# Output with thumb paths
echo "$CLIENTS" | jq -c \
    '[.[] | . + {thumbPath: ("/tmp/qs-dock-" + (.address | ltrimstr("0x")) + ".png")}]'
