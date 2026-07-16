#!/bin/sh
# Exit 0 when running on AC power (charger plugged / charging), 1 otherwise.
# Used by hypridle.conf to pick battery vs AC idle timeouts at fire time:
#   on-timeout = on-ac.sh && <ac-action>      # only when plugged in
#   on-timeout = on-ac.sh || <battery-action> # only when on battery
#
# Do not assume the firmware calls its adapter `AC`; common alternatives are
# ACAD, ADP0 and USB_C. Read sysfs in-process so this stays portable without
# spawning `cat` for every hypridle check.
for supply in /sys/class/power_supply/*; do
    [ -r "$supply/type" ] && [ -r "$supply/online" ] || continue
    IFS= read -r type < "$supply/type"
    case "$type" in
        Mains|USB|USB_C|USB_PD)
            IFS= read -r online < "$supply/online"
            [ "$online" = "1" ] && exit 0
            ;;
    esac
done
exit 1
