#!/usr/bin/env bash
# Live availability probe: prepare authentication for a suspend that never
# happens, then require the QML active-time safety timer to restore PAM.

set -euo pipefail

readonly LOCK_HELPER="$HOME/.config/quickshell/scripts/quickshell-lock.sh"
readonly LOCK_RUNTIME_CONFIG="${XDG_RUNTIME_DIR:-/run/user/$UID}/quickshell-lock/config/shell.qml"

read_prop() {
    timeout --foreground --kill-after=0.05s 0.2s \
        qs --path "$LOCK_RUNTIME_CONFIG" ipc prop get lock "$1" 2>/dev/null || true
}

"$LOCK_HELPER" lock
"$LOCK_HELPER" prepare-sleep
started="$(date +%s)"

for _ in {1..200}; do
    if [[ "$(read_prop sleepPreparing)" == "false" ]] \
            && [[ "$(read_prop secure)" == "true" ]] \
            && [[ "$(read_prop ready)" == "true" ]]; then
        elapsed="$(( $(date +%s) - started ))"
        if (( elapsed < 14 )); then
            printf 'sleep safety resumed too early after %ss\n' "$elapsed" >&2
            exit 1
        fi
        printf 'sleep-timeout-recovered elapsed=%ss\n' "$elapsed"
        exit 0
    fi
    sleep 0.1
done

printf 'sleep safety timer did not restore authentication\n' >&2
exit 1
