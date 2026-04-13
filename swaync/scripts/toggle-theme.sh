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

DOCK_DIR="$HOME/.config/nwg-dock-hyprland"
DOCK_STYLE="$DOCK_DIR/style.css"
DOCK_STYLE_LIGHT="$DOCK_DIR/style-light.css"
DOCK_STYLE_DARK="$DOCK_DIR/style-dark.css"

CUR_THEME="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")"

if [ "$CUR_THEME" = "$DARK_THEME" ]; then
    gsettings set org.gnome.desktop.interface gtk-theme "$LIGHT_THEME"
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
    cp "$STYLE_LIGHT"          "$SWAYNC_STYLE"
    cp "$SWAYOSD_STYLE_LIGHT"  "$SWAYOSD_STYLE"
    cp "$DOCK_STYLE_LIGHT"     "$DOCK_STYLE"
else
    gsettings set org.gnome.desktop.interface gtk-theme "$DARK_THEME"
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    cp "$STYLE_DARK"          "$SWAYNC_STYLE"
    cp "$SWAYOSD_STYLE_DARK"  "$SWAYOSD_STYLE"
    cp "$DOCK_STYLE_DARK"     "$DOCK_STYLE"
fi

swaync-client --reload-css

pkill swayosd-server 2>/dev/null
while pgrep -x swayosd-server >/dev/null; do
    sleep 0.1
done
swayosd-server -s "$SWAYOSD_STYLE" &
disown

pkill -x nwg-dock-hyprland 2>/dev/null
while pgrep -x nwg-dock-hyprland >/dev/null; do
    sleep 0.1
done
nwg-dock-hyprland -d -hd 0 -mb 6 -i 42 -nolauncher &
disown

exit 0
