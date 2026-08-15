#!/usr/bin/env bash
# Live hotplug probe: add and remove one headless Hyprland output while locked,
# requiring the Quickshell coverage handshake to become secure after each step.
# The recovered lock remains active for manual authentication.

set -euo pipefail

readonly LOCK_HELPER="$HOME/.config/quickshell/scripts/quickshell-lock.sh"
readonly LOCK_RUNTIME_CONFIG="${XDG_RUNTIME_DIR:-/run/user/$UID}/quickshell-lock/config/shell.qml"
new_output=""

cleanup() {
    if [[ -n "$new_output" ]]; then
        hyprctl output remove "$new_output" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

read_prop() {
    timeout --foreground --kill-after=0.05s 0.2s \
        qs --path "$LOCK_RUNTIME_CONFIG" ipc prop get lock "$1" 2>/dev/null || true
}

wait_for_coverage() {
    local expected_count="$1"

    for _ in {1..80}; do
        if [[ "$(read_prop screenCount)" == "$expected_count" ]] \
                && [[ "$(read_prop secure)" == "true" ]]; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

"$LOCK_HELPER" lock
mapfile -t before_outputs < <(hyprctl -j monitors all | jq -r '.[].name')
before_count="${#before_outputs[@]}"

hyprctl output create headless >/dev/null
for _ in {1..40}; do
    while IFS= read -r candidate; do
        known=false
        for original in "${before_outputs[@]}"; do
            if [[ "$candidate" == "$original" ]]; then
                known=true
                break
            fi
        done
        if [[ "$known" == false ]]; then
            new_output="$candidate"
            break
        fi
    done < <(hyprctl -j monitors all | jq -r '.[].name')
    [[ -n "$new_output" ]] && break
    sleep 0.1
done

if [[ -z "$new_output" ]]; then
    printf 'Hyprland did not expose the new headless output\n' >&2
    exit 1
fi

if ! wait_for_coverage "$((before_count + 1))"; then
    printf 'lock did not securely cover added output %s\n' "$new_output" >&2
    exit 1
fi

hyprctl output remove "$new_output" >/dev/null
removed_output="$new_output"
new_output=""

if ! wait_for_coverage "$before_count"; then
    printf 'lock did not recover securely after removing output %s\n' "$removed_output" >&2
    exit 1
fi

printf 'hotplug-secure output=%s base_count=%s\n' "$removed_output" "$before_count"
