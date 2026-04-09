#!/usr/bin/env bash

# 부팅 직후 외부 모니터가 인식될 때까지 잠시 대기
sleep 1

# 노트북 덮개가 닫혀 있는지 상태 파일 확인
if grep -q closed /proc/acpi/button/lid/*/state; then
    # 외부 모니터가 연결되어 있는지 확인
    if hyprctl monitors | grep -qE '\s(DP-|HDMI-|DVI-|VGA-)'; then
        # 덮개가 닫혀있고 외부 모니터가 있으므로 클램쉘 모드 진입 (내장 화면 끄기)
        hyprctl keyword monitor "eDP-1,disable"
    fi
    # 외부 모니터가 없다면 아무것도 하지 않음 (안전망)
fi
