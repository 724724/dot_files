#!/bin/bash

ICON="weather-clear-night"
DND_STATE=$(swaync-client -D)

if [ "$DND_STATE" = "true" ]; then
    swaync-client -d -sw
    notify-send -a "swaync-system" -u low -i "$ICON" "Do Not Disturb" "Off"
else
    notify-send -a "swaync-system" -u low -i "$ICON" "Do Not Disturb" "On"
    (sleep 3 && swaync-client -d -sw) &
fi
