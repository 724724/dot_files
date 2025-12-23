#!/usr/bin/env bash

# Light / Dark 에서 사용할 GTK3 테마 이름
LIGHT_THEME="Orchis-Light"
DARK_THEME="Orchis-Dark"

# 현재 GTK 테마 확인
CUR_THEME="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")"

if [ "$CUR_THEME" = "$DARK_THEME" ]; then
    # 다크 → 라이트
    gsettings set org.gnome.desktop.interface gtk-theme "$LIGHT_THEME" >/dev/null 2>&1
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' >/dev/null 2>&1
else
    # 라이트 (또는 다른 테마) → 다크
    gsettings set org.gnome.desktop.interface gtk-theme "$DARK_THEME" >/dev/null 2>&1
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' >/dev/null 2>&1
fi

exit 0

