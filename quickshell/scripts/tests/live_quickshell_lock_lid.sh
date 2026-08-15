#!/usr/bin/env bash
# Passive end-to-end probe for the production lid-close suspend path. The user
# closes and reopens the physical lid while this process watches kernel,
# compositor, clamshell, and lock state. It never initiates suspend itself.

set -euo pipefail

readonly RUNTIME_ROOT="${XDG_RUNTIME_DIR:-/run/user/$UID}"
readonly PENDING_DIR="$RUNTIME_ROOT/hypr-suspend-$UID.pending"
readonly LOCK_RUNTIME_CONFIG="$RUNTIME_ROOT/quickshell-lock/config/shell.qml"

read_prop() {
    timeout --foreground --kill-after=0.05s 0.25s \
        qs --path "$LOCK_RUNTIME_CONFIG" ipc prop get lock "$1" 2>/dev/null || true
}

lid_state() {
    if grep -q closed /proc/acpi/button/lid/*/state 2>/dev/null; then
        printf '%s\n' closed
    else
        printf '%s\n' open
    fi
}

if [[ "$(lid_state)" != "open" ]]; then
    printf '%s\n' "lid must be open before arming the test" >&2
    exit 1
fi

if ! hyprctl monitors -j | jq -e \
        'length == 1 and .[0].name == "eDP-1" and .[0].dpmsStatus == true' \
        >/dev/null; then
    printf '%s\n' "lid suspend test requires only the active eDP-1 output" >&2
    exit 1
fi

if [[ "$(pgrep -cx hypridle || true)" != "1" ]]; then
    printf '%s\n' "exactly one hypridle process must be running" >&2
    exit 1
fi

if systemctl --user is-active --quiet quickshell-lock.service; then
    printf '%s\n' "lock service must be inactive before the lid event" >&2
    exit 1
fi

IFS= read -r before_success < /sys/power/suspend_stats/success
IFS= read -r before_fail < /sys/power/suspend_stats/fail
printf 'lid-test-armed before_success=%s before_fail=%s\n' \
    "$before_success" "$before_fail"

completed=false
for _ in {1..1200}; do
    IFS= read -r after_success < /sys/power/suspend_stats/success
    if (( after_success > before_success )); then
        completed=true
        break
    fi
    sleep 0.25
done

if [[ "$completed" != true ]]; then
    printf '%s\n' "no completed suspend cycle was observed" >&2
    exit 1
fi

for _ in {1..240}; do
    if [[ "$(systemctl show systemd-suspend.service -p ActiveState --value)" == "inactive" ]] \
            && [[ "$(lid_state)" == "open" ]]; then
        break
    fi
    sleep 0.25
done

if [[ "$(systemctl show systemd-suspend.service -p ActiveState --value)" != "inactive" ]] \
        || [[ "$(lid_state)" != "open" ]]; then
    printf '%s\n' "resume did not settle with the lid open" >&2
    exit 1
fi

lock_ready=false
for _ in {1..160}; do
    if [[ "$(read_prop sleepPreparing)" == "false" ]] \
            && [[ "$(read_prop secure)" == "true" ]] \
            && [[ "$(read_prop ready)" == "true" ]]; then
        lock_ready=true
        break
    fi
    sleep 0.25
done

if [[ "$lock_ready" != true ]]; then
    printf '%s\n' "lock did not become secure and input-ready after lid resume" >&2
    exit 1
fi

IFS= read -r after_success < /sys/power/suspend_stats/success
IFS= read -r after_fail < /sys/power/suspend_stats/fail
if (( after_success != before_success + 1 )) || (( after_fail != before_fail )); then
    printf 'unexpected suspend counters: success %s->%s fail %s->%s\n' \
        "$before_success" "$after_success" "$before_fail" "$after_fail" >&2
    exit 1
fi

if [[ -d "$PENDING_DIR" ]]; then
    printf '%s\n' "clamshell pending flag remained after resume" >&2
    exit 1
fi

if ! hyprctl monitors -j | jq -e \
        'any(.[]; .name == "eDP-1" and .dpmsStatus == true and .disabled == false)' \
        >/dev/null; then
    printf '%s\n' "eDP-1 did not recover after lid resume" >&2
    exit 1
fi

if [[ "$(pgrep -cx hypridle || true)" != "1" ]]; then
    printf '%s\n' "hypridle was not preserved as one process" >&2
    exit 1
fi

printf 'lid-suspend-resume-secure before=%s after=%s\n' \
    "$before_success" "$after_success"
