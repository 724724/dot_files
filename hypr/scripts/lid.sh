#!/usr/bin/env bash
# MacBook-style clamshell mode for Hyprland.
# Usage: lid.sh close | open

set -euo pipefail

INTERNAL="eDP-1"
OVERRIDE="$HOME/.config/hypr/monitors.override.conf"
PIDFILE="/tmp/hypr-clamshell.pid"
LOG="/tmp/hypr-lid.log"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

is_power_connected() {
    local f
    for f in /sys/class/power_supply/A{C,DP}*/online; do
        [[ -r "$f" ]] && [[ "$(cat "$f")" == "1" ]] && return 0
    done
    return 1
}

external_monitor() {
    hyprctl monitors -j | jq -r --arg int "$INTERNAL" \
        'first(.[] | select(.name != $int and (.disabled // false) == false) | .name) // empty'
}

stop_inhibitor() {
    if [[ -f "$PIDFILE" ]]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
        rm -f "$PIDFILE"
    fi
}

start_inhibitor() {
    stop_inhibitor
    systemd-inhibit --what=sleep:idle --mode=block \
        --who="hypr-clamshell" --why="Clamshell mode active" \
        sleep infinity >/dev/null 2>&1 &
    echo $! >"$PIDFILE"
}

case "${1:-}" in
close)
    log "lid closed"
    ext=$(external_monitor)
    if is_power_connected && [[ -n "$ext" ]]; then
        log "clamshell: AC + external ($ext); disabling $INTERNAL"
        printf 'monitor=%s,disable\n' "$INTERNAL" >"$OVERRIDE"
        hyprctl reload >/dev/null
        hyprctl dispatch focusmonitor "$ext" >/dev/null
        start_inhibitor
    else
        log "no clamshell conditions; suspending"
        systemctl suspend
    fi
    ;;
open)
    log "lid opened"
    stop_inhibitor
    if [[ -f "$OVERRIDE" ]]; then
        rm -f "$OVERRIDE"
        hyprctl reload >/dev/null
    fi
    ;;
*)
    echo "Usage: $0 close|open" >&2
    exit 1
    ;;
esac
