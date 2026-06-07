#!/bin/sh
# Exit 0 when running on AC power (charger plugged / charging), 1 otherwise.
# Used by hypridle.conf to pick battery vs AC idle timeouts at fire time:
#   on-timeout = on-ac.sh && <ac-action>      # only when plugged in
#   on-timeout = on-ac.sh || <battery-action> # only when on battery
[ "$(cat /sys/class/power_supply/AC/online 2>/dev/null)" = "1" ]
