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
        hyprctl keyword monitor "eDP-1,disable"
    elif [ "$ACTION" = "open" ]; then
        hyprctl keyword monitor "eDP-1,3840x2400@60,320x1440,2"
    fi
else
    # [일반 모드] 외부 모니터가 없을 때
    if [ "$ACTION" = "close" ]; then
        systemctl suspend
    elif [ "$ACTION" = "open" ]; then
        # 🚨 핵심 수정: 여기서 강제로 keyword monitor를 다시 먹이지 마세요!
        # 그래픽 드라이버가 깨어나기도 전에 모니터를 재설정하면 렌더링이 멈춥니다.
        # 대신 화면(DPMS)만 확실히 켜지도록 명령합니다.
        hyprctl dispatch dpms on
    fi
fi

# Quickshell bar 재표시 (절전 복귀 시 타이밍 확보를 위해 sleep을 살짝 늘리는 것을 권장)
sleep 1
qs ipc -c desktop call bar reload 2>/dev/null || true
