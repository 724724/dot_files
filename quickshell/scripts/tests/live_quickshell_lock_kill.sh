#!/usr/bin/env bash
# Live recovery probe: acquire the real session lock, SIGKILL only its main
# process, then require systemd to launch a different PID that becomes secure.
# This deliberately leaves the recovered lock active for manual authentication.

set -euo pipefail

readonly LOCK_SERVICE="quickshell-lock.service"
readonly LOCK_HELPER="$HOME/.config/quickshell/scripts/quickshell-lock.sh"

"$LOCK_HELPER" lock
old_pid="$(systemctl --user show "$LOCK_SERVICE" -p MainPID --value)"
if [[ ! "$old_pid" =~ ^[1-9][0-9]*$ ]]; then
    printf 'invalid original MainPID: %s\n' "$old_pid" >&2
    exit 1
fi

systemctl --user kill --signal=KILL --kill-whom=main "$LOCK_SERVICE"

for _ in {1..50}; do
    new_pid="$(systemctl --user show "$LOCK_SERVICE" -p MainPID --value)"
    if [[ "$new_pid" =~ ^[1-9][0-9]*$ ]] && [[ "$new_pid" != "$old_pid" ]]; then
        if "$LOCK_HELPER" wait-secure; then
            printf 'recovered old_pid=%s new_pid=%s\n' "$old_pid" "$new_pid"
            exit 0
        fi
    fi
    sleep 0.1
done

printf 'lock service did not recover securely after SIGKILL (old_pid=%s)\n' "$old_pid" >&2
exit 1
