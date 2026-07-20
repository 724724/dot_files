#!/usr/bin/env bash
#
# clamshell.sh — macOS 클램쉘 모드 동작을 Hyprland에서 재현
#
#   덮개 닫힘 + AC 전원 + 외부 디스플레이  →  내장 패널 끄고 깨어있기 (클램쉘)
#   덮개 닫힘 (그 외)                       →  RAM 절전 (suspend)
#   덮개 열림 / suspend 복귀 후 lid open    →  내장 패널 복구
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
# 사용법: clamshell.sh [closed|open|resume|monitor-removed]
# 호출 위치: configs/keybindings.lua 의 Lid Switch 바인딩과 configs/autostart.lua 의 monitor.removed 이벤트

set -euo pipefail

INTERNAL="eDP-1"   # 내장 패널 (hyprctl monitors)
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/clamshell-${UID}.lock"

exec 9>"$LOCK_FILE"
flock -w 5 9 || exit 0

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
    hyprctl monitors -j 2>/dev/null | jq -e --arg i "$INTERNAL" \
        'any(.[]; .name != $i and (.name | test("^(FALLBACK|HEADLESS)") | not))' >/dev/null
}

hide_mission_control() {
    qs ipc -c desktop call -- mc hide >/dev/null 2>&1 || true
}

wait_hypr() {
    local i
    for i in {1..30}; do
        hyprctl monitors -j >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    return 1
}

dpms_on() {
    hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null 2>&1 || true
}

internal_active() {
    hyprctl monitors -j 2>/dev/null | jq -e --arg i "$INTERNAL" 'any(.[]; .name == $i)' >/dev/null
}

internal_spec() {
    awk -F= -v output="$INTERNAL" '
        $1 == "monitor" {
            split($2, p, ",")
            if (p[1] == output && p[2] != "disable" && p[2] != "disabled") {
                print p[2] "|" p[3] "|" p[4]
                exit
            }
        }
    ' "$HOME/.config/hypr/monitors.conf"
}

restore_internal() {
    wait_hypr || true
    dpms_on
    internal_active && return 0
    hide_mission_control

    note "restore $INTERNAL → hyprctl reload"
    hyprctl reload >/dev/null 2>&1 || true

    local delay
    for delay in 0.1 0.2 0.4 0.7; do
        sleep "$delay"
        dpms_on
        internal_active && return 0
    done

    local spec mode position scale
    spec="$(internal_spec || true)"
    if [[ -n "$spec" ]]; then
        IFS='|' read -r mode position scale <<< "$spec"
        if [[ -n "$mode" && -n "$position" && -n "$scale" ]]; then
            note "restore $INTERNAL fallback → hl.monitor eval"
            hyprctl eval "hl.monitor({ output = \"$INTERNAL\", mode = \"$mode\", position = \"$position\", scale = $scale })" >/dev/null 2>&1 || true
            sleep 0.2
            dpms_on
        fi
    fi

    internal_active && return 0
    note "restore $INTERNAL failed"
    return 1
}

disable_internal() {
    wait_hypr || true
    hide_mission_control
    sleep 0.15
    hyprctl eval "hl.monitor({ output = \"$INTERNAL\", disabled = true })" >/dev/null
}

case "${1:-$(lid_state)}" in
    closed)
        if on_ac && external_connected; then
            note "lid closed + AC + external → clamshell (disable $INTERNAL via lua eval)"
            disable_internal
        else
            note "lid closed, no dock/power → suspend"
            systemctl suspend                              # SuspendToRAM
        fi
        ;;
    open)
        note "lid open → restore $INTERNAL"
        restore_internal || true
        ;;
    resume)
        note "resume → apply lid state"
        if [[ "$(lid_state)" == "open" ]]; then
            restore_internal || true
        elif on_ac && external_connected; then
            disable_internal
        else
            dpms_on
        fi
        ;;
    monitor-removed)
        hide_mission_control
        sleep 0.15
        if [[ "$(lid_state)" == "open" ]]; then
            note "monitor removed + lid open → restore $INTERNAL"
            restore_internal || true
        elif external_connected; then
            note "monitor removed + lid closed + external remains → keep clamshell"
        else
            note "last external removed + lid closed → restore $INTERNAL before suspend"
            restore_internal || true
            if [[ "$(lid_state)" == "closed" ]]; then
                systemctl suspend
            fi
        fi
        ;;
esac
