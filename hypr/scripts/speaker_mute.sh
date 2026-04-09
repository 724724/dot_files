#!/bin/bash
wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle

if wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q "MUTED"; then
    brightnessctl -d 'platform::mute' set 1
else
    brightnessctl -d 'platform::mute' set 0
fi

# OSD 표시 (볼륨 0 변경 = 현재 상태만 표시)
swayosd-client --output-volume 0
