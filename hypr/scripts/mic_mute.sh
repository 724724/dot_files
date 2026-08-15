#!/bin/bash
SOURCES=()
while read -r SOURCE _; do
    [ -n "$SOURCE" ] && SOURCES+=("$SOURCE")
done < <(pactl list sources short)
# 현재 뮤트 상태 확인 (첫 번째 소스 기준)
FIRST_SOURCE="${SOURCES[0]:-}"
if [ -z "$FIRST_SOURCE" ]; then
    # 소스가 없으면 LED만 토글
    CURRENT=$(brightnessctl -d 'platform::micmute' get)
    if [ "$CURRENT" = "0" ]; then
        brightnessctl -d 'platform::micmute' set 1
    else
        brightnessctl -d 'platform::micmute' set 0
    fi
    exit 0
fi

MUTE_STATE=$(pactl get-source-mute "$FIRST_SOURCE")
if [[ "$MUTE_STATE" == *yes* ]]; then
    TARGET=0
else
    TARGET=1
fi

for SRC in "${SOURCES[@]}"; do
    pactl set-source-mute "$SRC" "$TARGET"
done

brightnessctl -d 'platform::micmute' set "$TARGET"
qs ipc -c desktop call osd micmute "$TARGET"
