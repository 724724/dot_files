#!/usr/bin/env bash
#
# Apple-style closed-display policy for Hyprland.
#
# Every relevant event converges on one state decision:
#
#   lid open                                  -> internal display on
#   lid closed + AC + active external display -> closed-display mode
#   lid closed + anything else                -> suspend
#
# Event sources:
#   Hyprland lid binds       -> closed / open
#   Hyprland monitor events  -> display-changed
#   udev power events        -> power-changed
#   hypridle after_sleep_cmd -> resume
#
# There are deliberately no fixed resume delays, polling loops, synthetic input
# events, or audio/driver workarounds here. Hardware and compositor events are
# the clocks for this state machine.

set -euo pipefail

readonly INTERNAL_DISPLAY="${CLAMSHELL_INTERNAL_DISPLAY:-eDP-1}"
readonly RUNTIME_ROOT="${XDG_RUNTIME_DIR:-/run/user/$UID}"
readonly ACTION_LOCK="$RUNTIME_ROOT/clamshell-policy-$UID.lock"
readonly LOCK_HELPER="$HOME/.config/quickshell/scripts/quickshell-lock.sh"
readonly SELF="$(readlink -f -- "${BASH_SOURCE[0]}")"

ACTION_FD_OPEN=false

note() {
    logger -t clamshell -- "$*" 2>/dev/null || true
}

lid_state() {
    local state_file state

    for state_file in /proc/acpi/button/lid/*/state; do
        [[ -r "$state_file" ]] || continue
        IFS= read -r state < "$state_file"
        case "$state" in
            *closed*) printf '%s\n' closed; return 0 ;;
            *open*)   printf '%s\n' open;   return 0 ;;
        esac
    done

    printf '%s\n' unknown
}

power_state() {
    local supply type online found=false

    for supply in /sys/class/power_supply/*; do
        [[ -r "$supply/type" && -r "$supply/online" ]] || continue
        IFS= read -r type < "$supply/type"
        [[ "$type" == "Mains" ]] || continue
        found=true
        IFS= read -r online < "$supply/online"
        if [[ "$online" == "1" ]]; then
            printf '%s\n' ac
            return 0
        fi
    done

    if [[ "$found" == true ]]; then
        printf '%s\n' battery
    else
        printf '%s\n' unknown
    fi
}

external_state() {
    local monitors

    if ! monitors="$(hyprctl monitors -j 2>/dev/null)"; then
        printf '%s\n' unknown
        return 0
    fi

    if ! jq -e 'type == "array"' <<<"$monitors" >/dev/null 2>&1; then
        printf '%s\n' unknown
        return 0
    fi

    if jq -e --arg internal "$INTERNAL_DISPLAY" '
        any(.[ ];
            .name != $internal
            and (.disabled // false) == false
            and (.name | test("^(FALLBACK|HEADLESS)") | not)
        )
    ' <<<"$monitors" >/dev/null; then
        printf '%s\n' active
    else
        printf '%s\n' absent
    fi
}

internal_active() {
    hyprctl monitors -j 2>/dev/null \
        | jq -e --arg internal "$INTERNAL_DISPLAY" '
            any(.[ ]; .name == $internal and (.disabled // false) == false)
        ' >/dev/null
}

# This is the same policy shape used by Apple's clamshell power decision.
# Unknown hardware/compositor state is fail-safe: wait for the next real event
# rather than disabling the only display or suspending on a guessed topology.
desired_mode() {
    local lid="$1" power="$2" external="$3"

    if [[ "$lid" == open ]]; then
        printf '%s\n' open
    elif [[ "$lid" != closed ]]; then
        printf '%s\n' wait
    elif [[ "$power" == battery ]]; then
        printf '%s\n' sleep
    elif [[ "$power" == unknown ]]; then
        printf '%s\n' wait
    elif [[ "$external" == active ]]; then
        printf '%s\n' clamshell
    elif [[ "$external" == absent ]]; then
        printf '%s\n' sleep
    else
        printf '%s\n' wait
    fi
}

dpms_on() {
    hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null 2>&1 || true
}

restore_internal() {
    dpms_on
    if internal_active; then
        return 0
    fi

    note "restore $INTERNAL_DISPLAY from monitor configuration"
    if ! hyprctl reload >/dev/null 2>&1; then
        note "failed to reload monitor configuration"
        return 1
    fi
    dpms_on
}

disable_internal() {
    dpms_on
    if ! internal_active; then
        return 0
    fi

    note "disable $INTERNAL_DISPLAY for closed-display mode"
    if ! hyprctl eval \
        "hl.monitor({ output = \"$INTERNAL_DISPLAY\", disabled = true })" \
        >/dev/null 2>&1; then
        note "failed to disable $INTERNAL_DISPLAY"
        return 1
    fi
}

preparing_for_sleep() {
    local preparing

    preparing="$(busctl --system get-property \
        org.freedesktop.login1 \
        /org/freedesktop/login1 \
        org.freedesktop.login1.Manager \
        PreparingForSleep 2>/dev/null || true)"
    [[ "$preparing" == "b true" ]]
}

release_action_lock() {
    if [[ "$ACTION_FD_OPEN" == true ]]; then
        flock -u 9 2>/dev/null || true
        exec 9>&-
        ACTION_FD_OPEN=false
    fi
}

policy_still_requests_sleep() {
    local lid power external

    lid="$(lid_state)"
    power="$(power_state)"
    external="$(external_state)"
    [[ "$(desired_mode "$lid" "$power" "$external")" == sleep ]]
}

request_suspend() {
    local reason="$1" policy_request="${2:-false}" status=0

    preparing_for_sleep && return 0

    if ! "$LOCK_HELPER" prepare-sleep; then
        note "suspend cancelled: session lock did not become sleep-ready"
        return 1
    fi

    # Lock acquisition can take a few seconds. A lid, power, or display event
    # during that handshake wins; never sleep using a stale snapshot.
    if [[ "$policy_request" == true ]] && ! policy_still_requests_sleep; then
        "$LOCK_HELPER" resume >/dev/null 2>&1 || true
        note "suspend cancelled: closed-display conditions changed"
        return 0
    fi

    note "suspend requested ($reason)"
    release_action_lock
    systemctl --no-ask-password suspend || status=$?

    if (( status != 0 )); then
        "$LOCK_HELPER" resume >/dev/null 2>&1 || true
        note "suspend request failed with status $status"
    fi
    return "$status"
}

reconcile() {
    local reason="$1" lid power external target

    lid="$(lid_state)"
    power="$(power_state)"
    external="$(external_state)"
    target="$(desired_mode "$lid" "$power" "$external")"

    note "reconcile reason=$reason lid=$lid power=$power external=$external target=$target"

    case "$target" in
        open)
            restore_internal || true
            ;;
        clamshell)
            # Recheck the volatile inputs immediately before removing eDP.
            if [[ "$(lid_state)" == closed \
                    && "$(power_state)" == ac \
                    && "$(external_state)" == active ]]; then
                disable_internal || true
            else
                note "closed-display transition skipped: conditions changed"
            fi
            ;;
        sleep)
            request_suspend "$reason" true || true
            ;;
        wait)
            note "no action: lid/power/display state is not yet reliable"
            ;;
    esac
}

watch_power() {
    local previous current

    previous="$(power_state)"
    note "power watcher started (state=$previous)"

    /usr/bin/udevadm monitor --udev --subsystem-match=power_supply 2>/dev/null \
        | while IFS= read -r _; do
            current="$(power_state)"
            [[ "$current" != "$previous" ]] || continue
            note "power source changed: $previous -> $current"
            previous="$current"
            "$SELF" power-changed || true
        done
}

print_status() {
    local lid power external target

    lid="$(lid_state)"
    power="$(power_state)"
    external="$(external_state)"
    target="$(desired_mode "$lid" "$power" "$external")"
    printf 'lid=%s power=%s external=%s target=%s\n' \
        "$lid" "$power" "$external" "$target"
}

main() {
    local action="${1:-reconcile}"

    case "$action" in
        watch-power)
            watch_power
            return
            ;;
        status)
            print_status
            return
            ;;
        lock)
            "$LOCK_HELPER" lock
            return
            ;;
        closed|open|display-changed|monitor-added|monitor-removed|power-changed|reconcile|resume|suspend)
            ;;
        *)
            printf 'usage: %s {closed|open|display-changed|power-changed|reconcile|resume|suspend|lock|status|watch-power}\n' \
                "$0" >&2
            return 2
            ;;
    esac

    exec 9>"$ACTION_LOCK"
    ACTION_FD_OPEN=true
    if ! flock -w 5 9; then
        # Even if a broken policy process held the lock too long, never leave
        # PAM/fingerprint state stranded in its pre-suspend phase.
        if [[ "$action" == resume ]]; then
            "$LOCK_HELPER" resume >/dev/null 2>&1 || true
        fi
        note "event dropped after action-lock timeout ($action)"
        return 1
    fi

    # Serialize lifecycle recovery with any concurrent sleep request, and do it
    # before display work so a renderer failure cannot skip authentication.
    if [[ "$action" == resume ]]; then
        if ! "$LOCK_HELPER" resume; then
            note "session lock failed to resume authentication"
        fi
    fi

    case "$action" in
        suspend)
            request_suspend idle false || true
            ;;
        *)
            reconcile "$action"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
