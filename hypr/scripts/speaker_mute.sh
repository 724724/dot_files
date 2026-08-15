#!/bin/bash
wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle

VOLUME=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
if [[ "$VOLUME" == *MUTED* ]]; then
    MUTED=1
else
    MUTED=0
fi

brightnessctl -d 'platform::mute' set "$MUTED"
qs ipc -c desktop call osd mute "$MUTED"
