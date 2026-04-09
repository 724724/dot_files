#!/usr/bin/env bash
if [ "$1" != "--run" ]; then
    nohup "$0" --run &>/dev/null &
    exit 0
fi

LIGHT_THEME="Adwaita"
DARK_THEME="Adwaita-dark"

SWAYNC_DIR="$HOME/.config/swaync"
SWAYNC_STYLE="$SWAYNC_DIR/style.css"
STYLE_LIGHT="$SWAYNC_DIR/style-light.css"
STYLE_DARK="$SWAYNC_DIR/style-dark.css"

SWAYOSD_DIR="$HOME/.config/swayosd"
SWAYOSD_STYLE="$SWAYOSD_DIR/style.css"
SWAYOSD_STYLE_LIGHT="$SWAYOSD_DIR/style-light.css"
SWAYOSD_STYLE_DARK="$SWAYOSD_DIR/style-dark.css"

CUR_THEME="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")"

if [ "$CUR_THEME" = "$DARK_THEME" ]; then
    gsettings set org.gnome.desktop.interface gtk-theme "$LIGHT_THEME"
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
    cp "$STYLE_LIGHT" "$SWAYNC_STYLE"
    cp "$SWAYOSD_STYLE_LIGHT" "$SWAYOSD_STYLE"
else
    gsettings set org.gnome.desktop.interface gtk-theme "$DARK_THEME"
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    cp "$STYLE_DARK" "$SWAYNC_STYLE"
    cp "$SWAYOSD_STYLE_DARK" "$SWAYOSD_STYLE"
fi

swaync-client --reload-css
# swayosd는 GTK 테마를 자동으로 따라가지만, CSS를 강제 적용하려면 재시작
pkill swayosd-server 2>/dev/null
sleep 0.2
swayosd-server &
disown

exit 0
