#!/bin/bash
# Outputs JSON with the currently active player's status/title/artist/artUrl.
# Routes through playerctld so the most-recently-active player is always picked.

PC="playerctl --player=playerctld"

STATUS=$($PC status 2>/dev/null)
if [ -z "$STATUS" ] || [ "$STATUS" = "Stopped" ]; then
    printf '{"status":"none","title":"","artist":"","artUrl":""}\n'
    exit 0
fi

TITLE=$($PC metadata --format '{{title}}'         2>/dev/null)
ARTIST=$($PC metadata --format '{{artist}}'       2>/dev/null)
ART=$($PC metadata --format '{{mpris:artUrl}}'    2>/dev/null)

# Use jq to JSON-encode safely (handles quotes, backslashes, unicode).
jq -nc --arg s "$STATUS" --arg t "$TITLE" --arg a "$ARTIST" --arg u "$ART" \
    '{status:$s, title:$t, artist:$a, artUrl:$u}'
