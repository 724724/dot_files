#!/usr/bin/env bash
# Focus guard for Hyprland app-launch keybindings.
#
# Runs "$@" (e.g. `kitty`, `nautilus`, or `gtk-launch <id>`) UNLESS a Pomodoro
# focus phase is currently active and the target app is not in that session's
# Allowed Apps. Blocked launches raise a notification instead of starting.
#
# State is written by the Quickshell clock (ClockService._recomputeFocus) to:
#   $XDG_RUNTIME_DIR/qs-focus-guard.json
#     { "active": bool, "allowedIds": [desktop-id...], "allowedExecs": [basename...] }
#
# Fail-open: if the file is missing/unreadable or focus is inactive, the app
# always launches — the guard never gets in the way outside of focus time.

guard="${XDG_RUNTIME_DIR:-/tmp}/qs-focus-guard.json"

[ "$#" -eq 0 ] && exit 0

# Replace this process with the requested command (Hyprland already detached us).
allow() { exec "$@"; }

# If the shell isn't running, the guard file is stale (it's only ever rewritten
# by the running shell). Without this, a crashed/killed Quickshell would leave
# every app locked with no way to unblock them.
pgrep -x qs >/dev/null 2>&1 || allow "$@"

active=false
if [ -r "$guard" ]; then
    active=$(jq -r '.active // false' "$guard" 2>/dev/null || echo false)
fi

# Not focusing → everything is allowed.
[ "$active" = "true" ] || allow "$@"

base=${1##*/}
allowed=false
if [ "$base" = "gtk-launch" ] && [ -n "${2:-}" ]; then
    # `gtk-launch <desktop-id>` — match on the desktop id.
    jq -e --arg id "$2" '(.allowedIds // []) | index($id)' "$guard" >/dev/null 2>&1 && allowed=true
else
    # Raw command — match on the executable's basename.
    jq -e --arg b "$base" '(.allowedExecs // []) | index($b)' "$guard" >/dev/null 2>&1 && allowed=true
fi

[ "$allowed" = "true" ] && allow "$@"

# Prefer the desktop id over the literal "gtk-launch" in the message.
name=$base
[ "$base" = "gtk-launch" ] && [ -n "${2:-}" ] && name=$2

notify-send -a Focus -u normal -i changes-prevent-symbolic \
    "Focus Mode" "\"${name}\" is blocked during focus time"
exit 0
