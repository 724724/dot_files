#!/usr/bin/env bash

# === 설정 ===
LIGHT_THEME="Adwaita"
DARK_THEME="Adwaita-dark"

# 배경화면 경로 설정 (수정된 부분)
WALL_LIGHT="$HOME/junk/wallpaper/wallpaper-light.png"
WALL_DARK="$HOME/junk/wallpaper/wallpaper-dark.png"

# SwayNC 설정 경로
SWAYNC_DIR="$HOME/.config/swaync"
SWAYNC_STYLE="$SWAYNC_DIR/style.css"
STYLE_LIGHT="$SWAYNC_DIR/style-light.css"
STYLE_DARK="$SWAYNC_DIR/style-dark.css"

# 현재 GTK 테마 확인 (없으면 prefer-light 가정)
CUR_THEME="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")"

if [ "$CUR_THEME" = "$DARK_THEME" ]; then
    # [ 다크 -> 라이트 전환 ]

    # 1. GTK 테마 및 색상 스키마 변경
    gsettings set org.gnome.desktop.interface gtk-theme "$LIGHT_THEME" >/dev/null 2>&1
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' >/dev/null 2>&1

    # 2. SwayNC 스타일 교체 (Light)
    cp "$STYLE_LIGHT" "$SWAYNC_STYLE"

    # 3. 배경화면 변경 (Light) --resize fit은 기존 contain 옵션과 동일
    swww img "$WALL_LIGHT" --resize fit --transition-type grow --transition-pos 0.9,0.9 --transition-step 90 --transition-duration 2

else
    # [ 라이트 -> 다크 전환 ]

    # 1. GTK 테마 및 색상 스키마 변경
    gsettings set org.gnome.desktop.interface gtk-theme "$DARK_THEME" >/dev/null 2>&1
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' >/dev/null 2>&1

    # 2. SwayNC 스타일 교체 (Dark)
    cp "$STYLE_DARK" "$SWAYNC_STYLE"

    # 3. 배경화면 변경 (Dark)
    swww img "$WALL_DARK" --resize fit --transition-type grow --transition-pos 0.9,0.9 --transition-step 90 --transition-duration 2
fi

# 4. SwayNC 스타일 새로고침 (CSS 리로드)
swaync-client --reload-css

exit 0
