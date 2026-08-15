#!/bin/bash
# Usage: media-osd.sh next | prev | play-pause
#
# Always routes through the playerctld daemon, which automatically targets the
# most-recently-active MPRIS player. This avoids the alphabetical-default
# behavior of plain `playerctl` (which would pick a stopped Chromium tab over
# a Playing Spotify, breaking the play/pause icon detection).

action="$1"
PC="playerctl --player=playerctld"

# Read title AND artist from a SINGLE metadata snapshot. The old version made
# two separate `playerctl metadata` calls, so a track change landing between
# them produced the new song's artist stitched onto the previous song's title.
# 0x1f (unit separator) can't occur in real metadata, so it's a safe delimiter.
read_label() {
    local meta artist title
    meta=$($PC metadata --format $'{{artist}}\x1f{{title}}' 2>/dev/null)
    artist=${meta%%$'\x1f'*}
    title=${meta#*$'\x1f'}
    if [ -n "$artist" ] && [ -n "$title" ]; then
        printf '%s — %s' "$artist" "$title"
    else
        printf '%s' "$title"
    fi
}

# Identity of the current track. Used to detect when a skip has actually landed
# on the new track instead of guessing with a fixed sleep.
track_key() {
    $PC metadata --format '{{mpris:trackid}}|{{title}}' 2>/dev/null
}

# Poll (up to ~1s) until the track key changes from $1, so the OSD reads the
# NEW track's metadata rather than racing the player's still-in-flight dbus
# update. Returns as soon as the change is seen; falls through on timeout so a
# single-track player (key never changes) still shows something.
wait_for_change() {
    local before="$1" now i
    for i in {1..25}; do
        now=$(track_key)
        [ -n "$now" ] && [ "$now" != "$before" ] && return 0
        sleep 0.04
    done
    return 1
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
        before=$(track_key)
        $PC next
        wait_for_change "$before"
        LABEL=$(read_label)
        qs ipc -c desktop call osd custom "󰒭" "${LABEL:-Next}"
        ;;
    prev)
        before=$(track_key)
        $PC previous
        wait_for_change "$before"
        LABEL=$(read_label)
        qs ipc -c desktop call osd custom "󰒮" "${LABEL:-Previous}"
        ;;
    play-pause)
        # Use the status we already read above as the BEFORE value — querying
        # again after `play-pause` would race with the player's dbus transition
        # and often return the stale state. The track doesn't change here, so
        # read_label is read immediately (no wait needed).
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
