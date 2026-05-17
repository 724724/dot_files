#!/usr/bin/env bash
# Toggle keyboard lock by enabling/disabling the internal keyboard device.
#
# Why this approach over submaps: Hyprland 0.55's Lua-wrapped `submap`
# dispatcher loses the special "break on submap handler" semantics, which
# breaks catchall-based key swallowing. Disabling the device directly is
# both simpler and 100% reliable.
#
# Which device to disable: keyd grabs `at-translated-set-2-keyboard` and
# forwards all keys through `keyd-virtual-keyboard`, so the virtual one is
# what Hyprland actually receives. Disabling the physical device does
# nothing. The XF86Display key fires on `thinkpad-extra-buttons` (a
# separate ACPI device, untouched by keyd), so it still works while the
# virtual keyboard is disabled — that's how unlock stays reachable.

DEVICE="keyd-virtual-keyboard"
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/keyboard-lock.state"

# Read current state from our own marker, since hyprctl getoption doesn't
# expose per-device enabled state cleanly.
# 0.55 uses Lua config — hyprctl keyword no longer accepts the legacy
# `device[name]:enabled` form. Use eval with hl.device() instead.
if [[ -f "$STATE_FILE" ]]; then
    # Currently locked → unlock
    hyprctl eval "hl.device({ name = \"$DEVICE\", enabled = true })" >/dev/null
    rm -f "$STATE_FILE"
    qs ipc -c desktop call osd custom "󰌆" "Keyboard Unlocked"
else
    # Currently unlocked → lock
    hyprctl eval "hl.device({ name = \"$DEVICE\", enabled = false })" >/dev/null
    touch "$STATE_FILE"
    qs ipc -c desktop call osd custom "󰌆" "Keyboard Locked"
fi
