#!/usr/bin/env bash
# Live suspend probe for the staged Quickshell lock. The existing manually
# launched hypridle is stopped only for this transaction, and is
# detached/restarted on every exit path.

set -euo pipefail

readonly LOCK_HELPER="$HOME/.config/quickshell/scripts/quickshell-lock.sh"
readonly LOCK_RUNTIME_CONFIG="${XDG_RUNTIME_DIR:-/run/user/$UID}/quickshell-lock/config/shell.qml"
hypridle_was_running=false
sleep_prepared=false

restart_hypridle() {
    if [[ "$hypridle_was_running" == true ]] && ! pgrep -x hypridle >/dev/null; then
        setsid -f /usr/bin/hypridle >/dev/null 2>&1
    fi
}

cleanup() {
    if [[ "$sleep_prepared" == true ]]; then
        "$LOCK_HELPER" resume >/dev/null 2>&1 || true
    fi
    restart_hypridle
}
trap cleanup EXIT

read_prop() {
    timeout --foreground --kill-after=0.05s 0.25s \
        qs --path "$LOCK_RUNTIME_CONFIG" ipc prop get lock "$1" 2>/dev/null || true
}

hypridle_pid="$(pgrep -xo hypridle || true)"
if [[ "$hypridle_pid" =~ ^[1-9][0-9]*$ ]]; then
    hypridle_was_running=true
    kill -TERM "$hypridle_pid"
    for _ in {1..30}; do
        pgrep -x hypridle >/dev/null || break
        sleep 0.1
    done
    if pgrep -x hypridle >/dev/null; then
        printf 'existing hypridle did not stop; refusing conflicting locker test\n' >&2
        exit 1
    fi
fi

"$LOCK_HELPER" lock
"$LOCK_HELPER" prepare-sleep
sleep_prepared=true
IFS= read -r before_success < /sys/power/suspend_stats/success

# `systemctl suspend` only queues the job. Keep PAM quiesced until the kernel
# records a completed cycle and the transient suspend service has finished its
# post-resume hooks; only then may the lock restart fingerprint/password auth.
systemctl suspend

suspend_completed=false
for _ in {1..600}; do
    IFS= read -r current_success < /sys/power/suspend_stats/success
    if (( current_success > before_success )) \
            && [[ "$(systemctl show systemd-suspend.service \
                -p ActiveState --value)" == "inactive" ]]; then
        suspend_completed=true
        break
    fi
    sleep 0.1
done

if [[ "$suspend_completed" != true ]]; then
    printf 'system did not complete a suspend cycle within the deadline\n' >&2
    exit 1
fi

"$LOCK_HELPER" resume
sleep_prepared=false

for _ in {1..120}; do
    if [[ "$(read_prop sleepPreparing)" == "false" ]] \
            && [[ "$(read_prop secure)" == "true" ]] \
            && [[ "$(read_prop ready)" == "true" ]]; then
        IFS= read -r after_success < /sys/power/suspend_stats/success
        if (( after_success <= before_success )); then
            printf 'system returned without a recorded suspend cycle\n' >&2
            exit 1
        fi
        restart_hypridle
        printf 'suspend-resume-secure before=%s after=%s\n' \
            "$before_success" "$after_success"
        exit 0
    fi
    sleep 0.1
done

printf 'lock did not become secure and ready after suspend resume\n' >&2
exit 1
