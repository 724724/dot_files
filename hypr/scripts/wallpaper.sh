#!/bin/bash

# 데몬이 이미 실행 중인지 확인하고 없으면 실행
if ! pgrep -x "swww-daemon" > /dev/null; then
    swww-daemon &
    sleep 0.5 
fi

# 배경화면 설정 (기존 contain 옵션 -> --resize fit)
# [possible values: no, crop, fit, stretch]
# 특정 모니터만 지정하고 싶다면 --outputs "eDP-1" 등을 추가하면 됩니다.
swww img /home/sejunlee/junk/wallpaper/wallpaper.jpeg --resize crop --transition-type none
