#!/usr/bin/env bash

# 외부 모니터가 DP-/HDMI-/DVI-/VGA- 로 잡힌다고 가정
if hyprctl monitors | grep -qE '\s(DP-|HDMI-|DVI-|VGA-)'; then
    # === 외부 모니터가 있을 때: 클램쉘 모드 구현 ===
    if [ "$1" = "close" ]; then
        # lid 닫힘 → 내장 디스플레이 끄기
        hyprctl keyword monitor "eDP-1,disable"
    elif [ "$1" = "open" ]; then
        # lid 열림 → eDP-1을 외부 모니터 바로 아래 중앙에 배치
        # (지금 쓰는 레이아웃에 맞춰 320x1440, scale 2)
        hyprctl keyword monitor "eDP-1,3840x2400@60,320x1440,2"
    fi
else
    # === 외부 모니터가 없을 때: 우리가 직접 suspend ===
    if [ "$1" = "close" ]; then
        systemctl suspend
    fi
    # open일 때는 resume 후 자동으로 켜져 있으니 아무 것도 안 해도 됨
fi

