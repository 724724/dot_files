#!/bin/bash

# 1. 스피커 음소거 토글
wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle

# 2. 현재 상태 확인 (MUTED 문자가 있으면 1, 없으면 0)
if wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q "MUTED"; then
    # 음소거 상태면 LED 켜기 (platform::mute 장치)
    brightnessctl -d 'platform::mute' set 1
else
    # 소리가 켜져 있으면 LED 끄기
    brightnessctl -d 'platform::mute' set 0
fi
