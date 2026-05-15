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

# 3. 외부 모니터 연결 여부 확인
if hyprctl monitors all | grep -qE '\s(DP-|HDMI-|DVI-|VGA-)'; then
    # [클램쉘 모드] 외부 모니터가 있을 때
    if [ "$ACTION" = "close" ]; then
        hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = true })'
    elif [ "$ACTION" = "open" ]; then
        hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "3840x2400@60", position = "320x1440", scale = 2 })'
    fi
else
    # [일반 모드] 외부 모니터가 없을 때
    if [ "$ACTION" = "close" ]; then
        systemctl suspend
    elif [ "$ACTION" = "open" ]; then
        # 화면만 즉시 켬 (Quickshell은 알아서 잘 살아남으므로 리로드 불필요!)
        hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'
    fi
fi
