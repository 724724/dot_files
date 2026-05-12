#!/bin/bash
wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle

if wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q "MUTED"; then
    brightnessctl -d 'platform::mute' set 1
else
    brightnessctl -d 'platform::mute' set 0
fi

if wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q "MUTED"; then
    qs ipc -c desktop call osd mute 1
else
    qs ipc -c desktop call osd mute 0
fi
