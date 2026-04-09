#!/usr/bin/env bash

# 1. 실행 인자 확인
ACTION="$1"

# 2. 인자가 없거나 'init'일 경우, 뚜껑 상태 읽어오기
if [[ -z "$ACTION" || "$ACTION" == "init" ]]; then
    if grep -q "closed" /proc/acpi/button/lid/*/state; then
        ACTION="close"
    else
        ACTION="open"
    fi
fi

# Waybar를 재시작할지 결정하는 플래그
RESTART_WAYBAR=false

# 3. 외부 모니터 연결 여부 확인
if hyprctl monitors all | grep -qE '\s(DP-|HDMI-|DVI-|VGA-)'; then
    if [ "$ACTION" = "close" ]; then
        hyprctl keyword monitor "eDP-1,disable"
        RESTART_WAYBAR=true
    elif [ "$ACTION" = "open" ]; then
        hyprctl keyword monitor "eDP-1,3840x2400@60,320x1440,2"
        RESTART_WAYBAR=true
    fi
else
    if [ "$ACTION" = "close" ]; then
        systemctl suspend
        # suspend 진입 시에는 어차피 깨어날 때 hypridle이 처리하므로 패스
    elif [ "$ACTION" = "open" ]; then
        hyprctl keyword monitor "eDP-1,3840x2400@60,0x0,2"
        RESTART_WAYBAR=true
    fi
fi

# 4. 모니터 상태가 변경되었다면 아주 잠깐(0.5초) 대기 후 Waybar 재시작
if [ "$RESTART_WAYBAR" = true ]; then
    sleep 0.5
    pkill waybar
    hyprctl dispatch exec waybar
fi
