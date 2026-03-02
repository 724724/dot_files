#!/bin/bash

# 데몬이 이미 실행 중인지 확인하고 없으면 실행
if ! pgrep -x "swww-daemon" > /dev/null; then
    swww-daemon &
    sleep 0.5 
fi

WALL_LIGHT="$HOME/junk/wallpaper/wallpaper_light.jpg"
WALL_DARK="$HOME/junk/wallpaper/wallpaper_dark.jpg"

# 배경화면 설정 (기존 contain 옵션 -> --resize fit)
# [possible values: no, crop, fit, stretch]
# 특정 모니터만 지정하고 싶다면 --outputs "eDP-1" 등을 추가하면 됩니다.
#swww img /home/sejunlee/junk/wallpaper/wallpaper.png --resize crop --transition-type none

if [ "$CUR_THEME" = "$DARK_THEME" ]; then
	swww img "$WALL_LIGHT" --resize crop --transition-type grow --transition-pos 0.9,0.9 --transition-step 90 --transition-duration 2
else
	swww img "$WALL_DARK" --resize crop --transition-type grow --transition-pos 0.9,0.9 --transition-step 90 --transition-duration 2
fi
