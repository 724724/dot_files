#!/bin/bash

# GNOME/GTK 설정에서 color-scheme 값을 가져옵니다.
# (대부분의 Linux 배포판에서 작동합니다)
THEME_MODE=$(gsettings get org.gnome.desktop.interface color-scheme)

# prefer-dark가 포함되어 있으면 다크 테마, 아니면 라이트 테마
if [[ "$THEME_MODE" == *"prefer-dark"* ]]; then
    rofi -show drun -theme ~/.config/rofi/spotlight-dark.rasi
else
    rofi -show drun -theme ~/.config/rofi/spotlight-light.rasi
fi
