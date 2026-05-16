#!/usr/bin/env bash
ACTION="$1"
if [[ -z "$ACTION" || "$ACTION" == "init" ]]; then
    if grep -q "closed" /proc/acpi/button/lid/*/state; then
        ACTION="close"
    else
        ACTION="open"
    fi
fi

if hyprctl monitors all | grep -qE '\s(DP-|HDMI-|DVI-|VGA-)'; then
    # 클램쉘 모드 (기존 로직 유지)
    if [ "$ACTION" = "close" ]; then
        hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = true })'
    elif [ "$ACTION" = "open" ]; then
        hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "3840x2400@60", position = "320x1440", scale = 2 })'
    fi
else
    # 일반 모드 — 변경됨
    if [ "$ACTION" = "close" ]; then
        # ★ suspend 전 eDP를 명시적으로 비활성화 (xe가 정리할 시간)
        hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = true })'
        sleep 0.3
        systemctl suspend
    elif [ "$ACTION" = "open" ]; then
        # ★ eDP를 다시 활성화 (resume 후 mode 재설정)
        hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 2 })'
        hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'
    fi
fi
