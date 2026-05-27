#!/bin/bash
# Raises the window of the media player currently shown in the NC media panel
# (whatever playerctld is proxying). Resolves the active player's process via
# D-Bus and maps it to a Hyprland window by PID — no app->class hardcoding, so
# it follows whatever is actually playing, with graceful fallbacks at each step.

SELF_DIR=$(dirname "$0")

# 1. Active player bus name. playerctld lists players most-recent-first, so the
#    first org.mpris.* entry is the one the panel is showing.
BUS=$(busctl --user get-property org.mpris.MediaPlayer2.playerctld \
        /org/mpris/MediaPlayer2 com.github.altdesktop.playerctld PlayerNames 2>/dev/null \
      | awk '{ for (i=1;i<=NF;i++) if ($i ~ /^"org\.mpris/) { gsub(/"/,"",$i); print $i; exit } }')
[ -z "$BUS" ] && exit 0

# 2. PID owning that bus name.
PID=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus GetConnectionUnixProcessID s "$BUS" 2>/dev/null \
      | awk '{print $2}')
[ -z "$PID" ] && exit 0

CLIENTS=$(hyprctl clients -j 2>/dev/null)
[ -z "$CLIENTS" ] && exit 0

# Address of the most-recently-focused window for a given pid (focusHistoryID
# ascending: 0 is the active window). Empty if that pid owns no window.
addr_for_pid() {
    echo "$CLIENTS" | jq -r --argjson p "$1" \
        'map(select(.pid == $p)) | sort_by(.focusHistoryID) | (.[0].address // empty)'
}

# 3. The MPRIS process and the window process can differ (e.g. a media helper
#    under a browser), so try the pid directly, then walk up the parent chain.
ADDR=""
P=$PID
for _ in 1 2 3 4 5 6; do
    ADDR=$(addr_for_pid "$P")
    [ -n "$ADDR" ] && break
    P=$(ps -o ppid= -p "$P" 2>/dev/null | tr -d ' ')
    { [ -z "$P" ] || [ "$P" -le 1 ]; } && break
done
[ -z "$ADDR" ] && exit 0

# 4. Focus it — reuses the cursor-move (defeats follow_mouse) + fallback logic.
exec "$SELF_DIR/focus-window.sh" "$ADDR"
