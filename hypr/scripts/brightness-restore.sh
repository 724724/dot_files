#!/bin/bash
# Restore screen brightness from the value saved by brightness-osd.sh.
# Called from Hyprland autostart and (when installed) the SDDM systemd unit.

STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/brightness"
[ -r "$STATE_FILE" ] || exit 0

PCT=$(tr -dc '0-9' < "$STATE_FILE")
[ -n "$PCT" ] || exit 0
[ "$PCT" -ge 1 ] && [ "$PCT" -le 100 ] || exit 0

brightnessctl set "${PCT}%" >/dev/null
