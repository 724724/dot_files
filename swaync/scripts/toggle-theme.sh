#!/usr/bin/env bash
# === 설정 ===
LIGHT_THEME="Adwaita"
DARK_THEME="Adwaita-dark"

# SwayNC 설정 경로
SWAYNC_DIR="$HOME/.config/swaync"
SWAYNC_STYLE="$SWAYNC_DIR/style.css"
STYLE_LIGHT="$SWAYNC_DIR/style-light.css"
STYLE_DARK="$SWAYNC_DIR/style-dark.css"

# AGS OSD 설정 경로
AGS_DIR="$HOME/.config/ags-osd"
AGS_STYLE="$AGS_DIR/style.css"
AGS_STYLE_LIGHT="$AGS_DIR/style-light.css"
AGS_STYLE_DARK="$AGS_DIR/style-dark.css"

# 현재 GTK 테마 확인 (없으면 prefer-light 가정)
CUR_THEME="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")"

if [ "$CUR_THEME" = "$DARK_THEME" ]; then
    # [ 다크 -> 라이트 전환 ]
    gsettings set org.gnome.desktop.interface gtk-theme "$LIGHT_THEME" >/dev/null 2>&1
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' >/dev/null 2>&1

    cp "$STYLE_LIGHT" "$SWAYNC_STYLE"
    cp "$AGS_STYLE_LIGHT" "$AGS_STYLE"
else
    # [ 라이트 -> 다크 전환 ]
    gsettings set org.gnome.desktop.interface gtk-theme "$DARK_THEME" >/dev/null 2>&1
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' >/dev/null 2>&1

    cp "$STYLE_DARK" "$SWAYNC_STYLE"
    cp "$AGS_STYLE_DARK" "$AGS_STYLE"
fi

# SwayNC 스타일 새로고침
swaync-client --reload-css

# AGS OSD 재시작 (CSS 반영)
ags quit -i osd 2>/dev/null
sleep 0.3
ags run -d "$AGS_DIR" &

exit 0
