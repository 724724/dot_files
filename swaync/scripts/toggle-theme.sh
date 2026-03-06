#!/usr/bin/env bash
if [ "$1" != "--run" ]; then
    nohup "$0" --run &>/dev/null &
    exit 0
fi

# === 설정 ===
LIGHT_THEME="Adwaita"
DARK_THEME="Adwaita-dark"
#WALL_LIGHT="$HOME/junk/wallpaper/wallpaper_light.jpg"
#WALL_DARK="$HOME/junk/wallpaper/wallpaper_dark.jpg"
SWAYNC_DIR="$HOME/.config/swaync"
SWAYNC_STYLE="$SWAYNC_DIR/style.css"
STYLE_LIGHT="$SWAYNC_DIR/style-light.css"
STYLE_DARK="$SWAYNC_DIR/style-dark.css"
AGS_DIR="$HOME/.config/ags-osd"
AGS_STYLE="$AGS_DIR/style.css"
AGS_STYLE_LIGHT="$AGS_DIR/style-light.css"
AGS_STYLE_DARK="$AGS_DIR/style-dark.css"

# 1) AGS 종료
ags quit -i osd 2>/dev/null

# 3) 테마 전환
CUR_THEME="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")"

if [ "$CUR_THEME" = "$DARK_THEME" ]; then
    gsettings set org.gnome.desktop.interface gtk-theme "$LIGHT_THEME" >/dev/null 2>&1
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' >/dev/null 2>&1
    cp "$STYLE_LIGHT" "$SWAYNC_STYLE"
    cp "$AGS_STYLE_LIGHT" "$AGS_STYLE"
    #swww img "$WALL_LIGHT" --resize crop --transition-type grow --transition-pos 0.9,0.9 --transition-step 90 --transition-duration 2
else
    gsettings set org.gnome.desktop.interface gtk-theme "$DARK_THEME" >/dev/null 2>&1
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' >/dev/null 2>&1
    cp "$STYLE_DARK" "$SWAYNC_STYLE"
    cp "$AGS_STYLE_DARK" "$AGS_STYLE"
    #swww img "$WALL_DARK" --resize crop --transition-type grow --transition-pos 0.9,0.9 --transition-step 90 --transition-duration 2
fi

# 4) swaync CSS 리로드
swaync-client --reload-css

# 5) AGS 재시작
ags run -d "$AGS_DIR" &
disown

exit 0
