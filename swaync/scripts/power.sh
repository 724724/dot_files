#!/bin/bash

ACTION="$1"  # shutdown, reboot, hibernate

# 테마 감지
if [[ "$(gsettings get org.gnome.desktop.interface color-scheme)" == *"dark"* ]]; then
  ROFI_THEME="$HOME/.config/rofi/confirm-dark.rasi"
else
  ROFI_THEME="$HOME/.config/rofi/confirm-light.rasi"
fi

# 실행 중인 GUI 앱 확인
EXCLUDE="foot|waybar|swaync|wofi|rofi|swww|dunst|Hyprland"
RUNNING_APPS=$(hyprctl clients -j | jq -r '.[].class' | grep -vE "^($EXCLUDE)$" | grep -v '^$' | sort -u)

if [ -n "$RUNNING_APPS" ]; then
  APP_COUNT=$(echo "$RUNNING_APPS" | wc -l)
  APP_LIST=$(echo "$RUNNING_APPS")
  
  case "$ACTION" in
    shutdown)  ACTION_LABEL="Shutdown" ;;
    reboot)    ACTION_LABEL="Reboot" ;;
    hibernate) ACTION_LABEL="Hibernate" ;;
    logout)    ACTION_LABEL="Logout" ;;
  esac

  CONFIRM=$(echo -e "Cancel\n$ACTION_LABEL" | rofi -dmenu \
    -theme "$ROFI_THEME" \
    -mesg "$APP_COUNT app(s) running:
    
$APP_LIST" \
    -a 1 \
    -p "")

  [ "$CONFIRM" != "$ACTION_LABEL" ] && exit 0
fi

case "$ACTION" in
  shutdown)  systemctl poweroff ;;
  reboot)    systemctl reboot ;;
  hibernate) systemctl hibernate ;;
  logout)    hyprctl dispatch exit ;;
esac
