#!/bin/bash
THEME_MODE=$(gsettings get org.gnome.desktop.interface color-scheme)
CALC_CMD="echo -n '{result}' | wl-copy"
MONITOR=$(hyprctl monitors -j | jq -r '.[] | select(.focused==true) | .name')

# fcitx5 XIM 연결 안정화
export XMODIFIERS="@im=fcitx"
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
fcitx5-remote -r 2>/dev/null  # IME 상태 리셋

if [[ "$THEME_MODE" == *"prefer-dark"* ]]; then
    rofi -show drun -theme ~/.config/rofi/spotlight-dark.rasi -calc-command "$CALC_CMD" -m "$MONITOR"
else
    rofi -show drun -theme ~/.config/rofi/spotlight-light.rasi -calc-command "$CALC_CMD" -m "$MONITOR"
fi
