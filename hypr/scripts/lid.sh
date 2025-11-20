#!/usr/bin/env bash

# 외부 모니터가 DP-/HDMI-로 잡힌다고 가정
if hyprctl monitors | grep -qE '\s(DP-|HDMI-|DVI-|VGA-)'; then
    if [ "$1" = "close" ]; then
        # lid 닫힘 → 내장 디스플레이 끄기
        hyprctl keyword monitor "eDP-1,disable"
    elif [ "$1" = "open" ]; then
        # lid 열림 → DP-2(0x0, scale 1.5) 바로 아래 중앙에 eDP-1 배치
        hyprctl keyword monitor "eDP-1,preferred,320x1440,2"
    fi
else
    # 외부 모니터 없으면: logind가 lid 닫을 때 suspend 하도록 둠
    :
fi
