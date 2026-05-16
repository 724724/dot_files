#!/usr/bin/env bash
# Power action runner. Confirmation lives in CCDetailPower.qml. We're invoked
# with the qs-detached process as our parent so it's safe to do longer work
# (graceful close + sleep) before issuing the actual systemctl/hyprctl call.

ACTION="$1"

# Ask every Hyprland client to close its window (WM_DELETE_WINDOW). Apps like
# VSCode rely on this to mark their last session as cleanly closed; without
# it, hyprctl exit kills them and they reopen with the "previous session
# wasn't closed" prompt.
graceful_close() {
    if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        local addrs
        addrs=$(hyprctl clients -j 2>/dev/null | jq -r '.[].address' 2>/dev/null)
        for addr in $addrs; do
            [ -n "$addr" ] && hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null 2>&1
        done
    fi
}

case "$ACTION" in
    shutdown)
        graceful_close
        sleep 1.2
        systemctl poweroff
        ;;
    reboot)
        graceful_close
        sleep 1.2
        systemctl reboot
        ;;
    hibernate)
        # Hibernate doesn't kill apps; skip graceful close.
        systemctl hibernate
        ;;
    logout)
        graceful_close
        sleep 1.2
        hyprctl dispatch 'hl.dsp.exit()'
        ;;
    lock)
        # Direct invocation — loginctl lock-session relies on hypridle's
        # LockSession listener which can be fragile, so just launch hyprlock
        # ourselves and detach so it survives this script exiting.
        if ! pidof hyprlock >/dev/null 2>&1; then
            setsid -f hyprlock </dev/null >/dev/null 2>&1
        fi
        ;;
    *)
        echo "usage: $0 {shutdown|reboot|hibernate|logout|lock}" >&2
        exit 1
        ;;
esac
