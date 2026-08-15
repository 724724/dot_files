#!/usr/bin/env bash
# Acquire the dedicated Quickshell session lock and do not report success until
# the compositor confirms that every output is covered.

set -euo pipefail

readonly LOCK_SERVICE="quickshell-lock.service"
readonly LOCK_RUNTIME_CONFIG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-lock/config/shell.qml"
# Keep this below clamshell.sh's 5-second flock budget. A slow acquisition
# cancels suspend, while the compositor/lock service remain fail-closed.
readonly WAIT_MILLISECONDS=3000
readonly WAIT_DELAY=0.1
readonly IPC_TIMEOUT=0.15s
readonly IPC_KILL_AFTER=0.05s
readonly LIFECYCLE_TIMEOUT=0.3s

sync_graphical_environment() {
    local -a names=()

    # The user manager does not inherit variables added after login. grim can
    # use WAYLAND_DISPLAY directly, while hyprctl also needs the exact running
    # compositor instance. Import only values that this lock request actually
    # inherited from Hyprland/hypridle.
    [[ -n "${WAYLAND_DISPLAY:-}" ]] && names+=(WAYLAND_DISPLAY)
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && names+=(HYPRLAND_INSTANCE_SIGNATURE)
    [[ -n "${XDG_RUNTIME_DIR:-}" ]] && names+=(XDG_RUNTIME_DIR)
    ((${#names[@]} > 0)) || return 0

    if ! systemctl --user import-environment "${names[@]}"; then
        logger -t quickshell-lock -- "failed to synchronize the graphical environment"
        return 1
    fi
}

is_secure() {
    local value
    value="$(timeout --foreground --kill-after="$IPC_KILL_AFTER" "$IPC_TIMEOUT" \
        qs --path "$LOCK_RUNTIME_CONFIG" ipc prop get lock secure 2>/dev/null || true)"
    [[ "$value" == "true" ]]
}

wait_secure() {
    local deadline

    deadline=$(( $(date +%s%3N) + WAIT_MILLISECONDS ))
    while (( $(date +%s%3N) < deadline )); do
        is_secure && return 0
        sleep "$WAIT_DELAY"
    done

    is_secure
}

acquire_lock() {
    is_secure && return 0

    sync_graphical_environment || return 1
    if ! systemctl --user start --no-block "$LOCK_SERVICE"; then
        logger -t quickshell-lock -- "failed to start $LOCK_SERVICE"
        return 1
    fi

    if wait_secure; then
        return 0
    fi

    logger -t quickshell-lock -- "lock acquisition timed out before compositor secure confirmation"
    return 1
}

call_lifecycle() {
    local function_name="$1"
    local result

    result="$(timeout --foreground --kill-after="$IPC_KILL_AFTER" "$LIFECYCLE_TIMEOUT" \
        qs --path "$LOCK_RUNTIME_CONFIG" ipc call lock "$function_name" 2>/dev/null || true)"
    [[ "$result" == "true" ]]
}

prepare_sleep() {
    acquire_lock || return 1

    if ! call_lifecycle prepareForSleep; then
        # The state change may have committed even if the reply was delayed.
        # Resume is idempotent, so use it as a bounded availability rollback.
        call_lifecycle resumeFromSleep >/dev/null 2>&1 || true
        logger -t quickshell-lock -- "lock refused the prepare-for-sleep handshake"
        return 1
    fi

    # PamContext aborts its subprocess synchronously. Give fprintd's D-Bus
    # client teardown a brief moment to release the exclusive sensor claim.
    sleep 0.1
}

resume_from_sleep() {
    local deadline

    # Resume the surviving instance before waiting for output coverage. During
    # DRM recovery `secure` can legitimately remain false for several seconds,
    # while this call is precisely what clears sleepPreparing and lets coverage
    # completion restart PAM.
    call_lifecycle resumeFromSleep && return 0

    sync_graphical_environment || return 1
    if ! systemctl --user start --no-block "$LOCK_SERVICE"; then
        logger -t quickshell-lock -- "failed to start $LOCK_SERVICE during resume"
        return 1
    fi

    deadline=$(( $(date +%s%3N) + WAIT_MILLISECONDS ))
    while (( $(date +%s%3N) < deadline )); do
        call_lifecycle resumeFromSleep && return 0
        sleep "$WAIT_DELAY"
    done

    logger -t quickshell-lock -- "lock refused the resume-from-sleep handshake"
    return 1
}

print_status() {
    if is_secure; then
        printf '%s\n' secure
        return 0
    fi

    if systemctl --user is-active --quiet "$LOCK_SERVICE"; then
        printf '%s\n' acquiring
    elif systemctl --user is-failed --quiet "$LOCK_SERVICE"; then
        printf '%s\n' failed
    else
        printf '%s\n' unlocked
    fi

    return 1
}

case "${1:-lock}" in
    lock)
        acquire_lock
        ;;
    wait-secure)
        wait_secure
        ;;
    prepare-sleep)
        prepare_sleep
        ;;
    resume)
        resume_from_sleep
        ;;
    status)
        print_status
        ;;
    *)
        printf 'usage: %s {lock|wait-secure|prepare-sleep|resume|status}\n' "$0" >&2
        exit 2
        ;;
esac
