#!/bin/bash
# 1. 마이크 음소거 토글
wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle

# 2. 현재 상태 확인 후 LED 제어
if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q "MUTED"; then
    brightnessctl -d 'platform::micmute' set 1
else
    brightnessctl -d 'platform::micmute' set 0
fi
