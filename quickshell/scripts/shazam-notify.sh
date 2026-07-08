#!/usr/bin/env bash
# Desktop notification for a recognized song: album art + title + artist with
# a "View on Shazam" action. Meant to be launched detached — notify-send
# --action implies --wait, so this process stays alive in the background until
# the toast is dismissed or actioned, which is how the button keeps working
# after the Shazam popup is closed.
#
#   shazam-notify.sh <title> <artist> <coverLocalPath> <songUrl>
TITLE="${1:-Unknown track}"
ARTIST="${2:-}"
COVER="${3:-}"
LINK="${4:-}"

ARGS=(--app-name="Music Recognition" --urgency=normal)
[ -n "$COVER" ] && ARGS+=(--icon="$COVER")
[ -n "$LINK" ]  && ARGS+=(--action="open=View on Shazam")

# --wait makes notify-send print the chosen action's name to stdout.
ACTION="$(notify-send "${ARGS[@]}" --wait "$TITLE" "$ARTIST" 2>/dev/null)"

if [ "$ACTION" = "open" ] && [ -n "$LINK" ]; then
    xdg-open "$LINK" >/dev/null 2>&1
fi
