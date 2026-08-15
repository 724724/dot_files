#!/usr/bin/env bash
# Live DPMS probe: power the focused output off and back on while the real
# session lock is held, then require secure coverage and password readiness.

set -euo pipefail

readonly LOCK_HELPER="$HOME/.config/quickshell/scripts/quickshell-lock.sh"
readonly LOCK_RUNTIME_CONFIG="${XDG_RUNTIME_DIR:-/run/user/$UID}/quickshell-lock/config/shell.qml"
output="$(hyprctl -j monitors | jq -r 'map(select(.focused))[0].name // .[0].name // empty')"

if [[ -z "$output" ]]; then
    printf 'no active Hyprland output found\n' >&2
    exit 1
fi

restore_dpms() {
    hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null 2>&1 || true
}
trap restore_dpms EXIT

read_monitor_dpms() {
    hyprctl -j monitors | jq -r --arg output "$output" \
        'map(select(.name == $output))[0].dpmsStatus // false'
}

read_lock_prop() {
    timeout --foreground --kill-after=0.05s 0.2s \
        qs --path "$LOCK_RUNTIME_CONFIG" ipc prop get lock "$1" 2>/dev/null || true
}

"$LOCK_HELPER" lock
# Hyprland 0.56 dispatchers use the Lua API. Judge the real monitor state below
# as well, since powering down can close the control reply after it commits.
hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })' >/dev/null 2>&1 || true

for _ in {1..30}; do
    [[ "$(read_monitor_dpms)" == "false" ]] && break
    sleep 0.1
done
if [[ "$(read_monitor_dpms)" != "false" ]]; then
    printf 'output %s did not enter DPMS off\n' "$output" >&2
    exit 1
fi

sleep 2
hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null 2>&1 || true

for _ in {1..50}; do
    if [[ "$(read_monitor_dpms)" == "true" ]] \
            && [[ "$(read_lock_prop secure)" == "true" ]] \
            && [[ "$(read_lock_prop ready)" == "true" ]]; then
        trap - EXIT
        printf 'dpms-secure output=%s\n' "$output"
        exit 0
    fi
    sleep 0.1
done

printf 'lock did not become ready after DPMS on for %s\n' "$output" >&2
exit 1
