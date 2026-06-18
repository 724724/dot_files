#!/usr/bin/env bash
#
# clamshell.sh — macOS 클램쉘 모드 동작을 Hyprland에서 재현
#
#   덮개 닫힘 + AC 전원 + 외부 디스플레이  →  내장 패널 끄고 깨어있기 (클램쉘)
#   덮개 닫힘 (그 외)                       →  RAM 절전 (suspend)
#   덮개 열림                               →  내장 패널 복구
#
# ── Lua(non-legacy) 파서 주의 ────────────────────────────────────────────────
# 이 설정은 hyprland.lua(0.55+) 파서를 쓴다. 그래서 `hyprctl keyword monitor ...`는
#   "keyword can't work with non-legacy parsers. Use eval."
# 로 무음 실패한다(에러를 내도 exit 0이라 성공한 척한다). 반드시 eval/reload를 쓸 것:
#   - 내장 끄기 : hyprctl eval 'hl.monitor({ ..., disabled = true })'
#                 → eDP-1이 빠지면서 그 위 워크스페이스가 외부 모니터로 자동 이동한다.
#   - 내장 복구 : hyprctl reload
#                 → monitors.conf(설정의 source of truth)를 다시 적용해 eDP-1을 되살린다.
#                 hl.monitor()를 다시 호출하는 것만으로는 0.55에서 재활성화가 안 된다(reload 필요).
#                 reload는 autostart(hl.on "hyprland.start")를 재실행하지 않으므로 앱 중복 없음.
#
# 사용법: clamshell.sh [closed|open]   (인자 없으면 /proc 에서 현재 lid 상태 감지)
# 호출 위치: configs/keybindings.lua 의 switch:Lid Switch 바인딩

set -euo pipefail

INTERNAL="eDP-1"   # 내장 패널 (hyprctl monitors)

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
            note "lid closed + AC + external → clamshell (disable $INTERNAL via lua eval)"
            # 내장 패널 OFF → 워크스페이스가 외부 모니터로 자동 이동
            hyprctl eval "hl.monitor({ output = \"$INTERNAL\", disabled = true })" >/dev/null
        else
            note "lid closed, no dock/power → suspend"
            systemctl suspend                              # SuspendToRAM
        fi
        ;;
    open)
        note "lid open → restore $INTERNAL (hyprctl reload)"
        hyprctl reload >/dev/null                          # monitors.conf 재적용으로 eDP-1 복구
        ;;
esac
