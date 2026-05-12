#!/usr/bin/env bash
# Flip GTK + color-scheme between light and dark. Quickshell components watch
# gsettings color-scheme and re-theme themselves automatically.

LIGHT_THEME="Adwaita"
DARK_THEME="Adwaita-dark"

CUR="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")"

if [ "$CUR" = "$DARK_THEME" ]; then
    gsettings set org.gnome.desktop.interface gtk-theme "$LIGHT_THEME"
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
else
    gsettings set org.gnome.desktop.interface gtk-theme "$DARK_THEME"
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
fi
