#!/bin/bash
# Usage: media-osd.sh next | prev | play-pause
#
# Always routes through the playerctld daemon, which automatically targets the
# most-recently-active MPRIS player. This avoids the alphabetical-default
# behavior of plain `playerctl` (which would pick a stopped Chromium tab over
# a Playing Spotify, breaking the play/pause icon detection).

action="$1"
PC="playerctl --player=playerctld"

read_label() {
    local title artist
    title=$($PC metadata --format '{{title}}' 2>/dev/null)
    artist=$($PC metadata --format '{{artist}}' 2>/dev/null)
    if [ -n "$artist" ] && [ -n "$title" ]; then
        printf '%s — %s' "$artist" "$title"
    else
        printf '%s' "$title"
    fi
}

# No active media — show a clear "nothing playing" OSD and exit.
# Pass "" as the icon (the OSD's `custom` IPC requires both icon and message
# args; an empty icon hides the icon column, leaving text only).
STATUS=$($PC status 2>/dev/null)
if [ -z "$STATUS" ] || [ "$STATUS" = "Stopped" ]; then
    qs ipc -c desktop call osd custom "" "There is no playable media"
    exit 0
fi

case "$action" in
    next)
        $PC next
        sleep 0.2
        LABEL=$(read_label)
        qs ipc -c desktop call osd custom "󰒭" "${LABEL:-Next}"
        ;;
    prev)
        $PC previous
        sleep 0.2
        LABEL=$(read_label)
        qs ipc -c desktop call osd custom "󰒮" "${LABEL:-Previous}"
        ;;
    play-pause)
        # Use the status we already read above as the BEFORE value — querying
        # again after `play-pause` would race with the player's dbus transition
        # and often return the stale state.
        BEFORE="$STATUS"
        $PC play-pause
        LABEL=$(read_label)
        if [ "$BEFORE" = "Playing" ]; then
            qs ipc -c desktop call osd custom "󰏤" "${LABEL:-Paused}"
        else
            qs ipc -c desktop call osd custom "󰐊" "${LABEL:-Playing}"
        fi
        ;;
    *)
        exit 1
        ;;
esac
