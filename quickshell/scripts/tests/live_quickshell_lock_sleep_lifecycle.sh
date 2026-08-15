#!/usr/bin/env bash
# Live lifecycle probe: pause both PAM conversations through the public
# pre-sleep handshake, resume them, and leave the real lock active for auth.

set -euo pipefail

readonly LOCK_HELPER="$HOME/.config/quickshell/scripts/quickshell-lock.sh"
readonly LOCK_RUNTIME_CONFIG="${XDG_RUNTIME_DIR:-/run/user/$UID}/quickshell-lock/config/shell.qml"

read_prop() {
    timeout --foreground --kill-after=0.05s 0.2s \
        qs --path "$LOCK_RUNTIME_CONFIG" ipc prop get lock "$1" 2>/dev/null || true
}

"$LOCK_HELPER" lock
"$LOCK_HELPER" prepare-sleep

if [[ "$(read_prop sleepPreparing)" != "true" ]] \
        || [[ "$(read_prop ready)" != "false" ]] \
        || [[ "$(read_prop fingerprintActive)" != "false" ]]; then
    "$LOCK_HELPER" resume >/dev/null 2>&1 || true
    printf 'lock did not quiesce authentication for sleep\n' >&2
    exit 1
fi

"$LOCK_HELPER" resume
for _ in {1..50}; do
    if [[ "$(read_prop sleepPreparing)" == "false" ]] \
            && [[ "$(read_prop secure)" == "true" ]] \
            && [[ "$(read_prop ready)" == "true" ]]; then
        printf 'sleep-lifecycle-secure\n'
        exit 0
    fi
    sleep 0.1
done

printf 'authentication did not become ready after lifecycle resume\n' >&2
exit 1
