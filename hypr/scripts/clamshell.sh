#!/usr/bin/env bash
#
# clamshell.sh — macOS 클램쉘 모드 동작을 Hyprland에서 재현
#
#   덮개 닫힘 + AC 전원 + 외부 디스플레이  →  내장 패널 끄고 깨어있기 (클램쉘)
#   덮개 닫힘 (그 외)                       →  RAM 절전 (suspend)
#   덮개 열림                               →  내장 패널 복구
#
# 사용법: clamshell.sh [closed|open]   (인자 없으면 /proc 에서 현재 lid 상태 감지)
# 호출 위치: configs/keybindings.lua 의 switch:Lid Switch 바인딩

set -euo pipefail

INTERNAL="eDP-1"   # 내장 패널 (hyprctl monitors)

# 내장 패널 복구 라인 — monitors.lua/monitors.conf 의 eDP-1 설정과 동일하게 유지할 것
# (nwg-displays 로 모니터 설정을 바꾸면 이 값도 같이 갱신)
INTERNAL_RESTORE="$INTERNAL, 3840x2400@60.0, 314x1440, 2.0, bitdepth, 10"

note() { logger -t clamshell -- "$*"; }

# 현재 lid 상태 (인자 미지정 시 fallback)
lid_state() {
    if grep -q closed /proc/acpi/button/lid/*/state 2>/dev/null; then
        echo closed
    else
        echo open
    fi
}

# 1) AC 어댑터 연결 여부  (pseudocode: System.Power.isAdapterConnected)
on_ac() {
    local ps
    for ps in /sys/class/power_supply/*; do
        [[ "$(cat "$ps/type" 2>/dev/null)" == "Mains" ]] || continue
        [[ "$(cat "$ps/online" 2>/dev/null)" == "1" ]] && return 0
    done
    return 1
}

# 2) 내장 외 외부 디스플레이 활성 여부  (pseudocode: isExternalDisplayActive)
external_connected() {
    hyprctl monitors -j | jq -e --arg i "$INTERNAL" 'any(.[]; .name != $i)' >/dev/null
}

case "${1:-$(lid_state)}" in
    closed)
        if on_ac && external_connected; then
            note "lid closed + AC + external → clamshell (disable $INTERNAL)"
            hyprctl keyword monitor "$INTERNAL, disable"   # 내장 화면 OFF → 워크스페이스 외부로 자동 이동
        else
            note "lid closed, no dock/power → suspend"
            systemctl suspend                              # SuspendToRAM
        fi
        ;;
    open)
        note "lid open → restore $INTERNAL"
        hyprctl keyword monitor "$INTERNAL_RESTORE"        # 내장 화면 복구
        ;;
esac
