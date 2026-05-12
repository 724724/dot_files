#!/bin/bash
# 모든 오디오 소스 음소거 토글
SOURCES=$(pactl list sources short | awk '{print $1}')
# 현재 뮤트 상태 확인 (첫 번째 소스 기준)
FIRST_SOURCE=$(echo "$SOURCES" | head -1)
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

IS_MUTED=$(pactl get-source-mute "$FIRST_SOURCE" | grep -c "yes")

for SRC in $SOURCES; do
    if [ "$IS_MUTED" = "1" ]; then
        pactl set-source-mute "$SRC" 0
    else
        pactl set-source-mute "$SRC" 1
    fi
done

if [ "$IS_MUTED" = "1" ]; then
    brightnessctl -d 'platform::micmute' set 0
else
    brightnessctl -d 'platform::micmute' set 1
fi

if [ "$IS_MUTED" = "1" ]; then
    qs ipc -c desktop call osd micmute 0
else
    qs ipc -c desktop call osd micmute 1
fi
