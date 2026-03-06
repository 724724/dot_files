#!/usr/bin/env bash
# 카메라 + 마이크 사용 감지 (하나의 waybar 모듈)

cam_active=0
mic_active=0

# ── 카메라 감지 ──
for dev in /dev/video*; do
    [ -e "$dev" ] || continue
    if fuser "$dev" 2>/dev/null | grep -q '[0-9]'; then
        cam_active=1
        break
    fi
done

if [ "$cam_active" -eq 0 ] && command -v pw-cli &>/dev/null; then
    if pw-cli ls Node 2>/dev/null | grep -qi "camera.*running\|video.*running"; then
        cam_active=1
    fi
fi

# ── 마이크 감지 ──
# Corked: no인 source-output이 있고, 해당 소스 또는 source-output이 뮤트가 아닌 경우
if command -v pactl &>/dev/null; then
    # source-output 중 Corked: no이고 Mute: no인 것
    in_block=0
    corked_no=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^Source\ Output ]]; then
            in_block=1
            corked_no=0
        elif [ "$in_block" -eq 1 ]; then
            if [[ "$line" =~ Corked:\ no ]]; then
                corked_no=1
            elif [[ "$line" =~ Mute:\ no ]] && [ "$corked_no" -eq 1 ]; then
                mic_active=1
                break
            elif [[ "$line" =~ Mute:\ yes ]] && [ "$corked_no" -eq 1 ]; then
                # 스트림은 활성이지만 뮤트됨 → 표시 안함
                corked_no=0
            fi
        fi
    done < <(pactl list source-outputs 2>/dev/null)

    # 기본 소스(마이크 자체)가 뮤트인지도 확인
    if [ "$mic_active" -eq 1 ]; then
        default_source=$(pactl get-default-source 2>/dev/null)
        if [ -n "$default_source" ]; then
            src_muted=$(pactl get-source-mute "$default_source" 2>/dev/null)
            if [[ "$src_muted" == *"yes"* ]]; then
                mic_active=0
            fi
        fi
    fi
fi

# ── 출력 조합 ──
if [ "$cam_active" -eq 1 ] && [ "$mic_active" -eq 1 ]; then
    echo '{"text":"  ","class":"active","tooltip":"Camera &amp; Microphone in use"}'
elif [ "$cam_active" -eq 1 ]; then
    echo '{"text":"","class":"active","tooltip":"Camera in use"}'
elif [ "$mic_active" -eq 1 ]; then
    echo '{"text":"","class":"active","tooltip":"Microphone in use"}'
else
    echo '{"text":"","class":"inactive"}'
fi
