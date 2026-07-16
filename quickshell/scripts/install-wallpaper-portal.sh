#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BACKEND="$SCRIPT_DIR/wallpaper-portal.py"
PORTAL_DIR="$ROOT_DIR/portal"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DBUS_SERVICE_DIR="$DATA_HOME/dbus-1/services"
XDG_PORTAL_DIR="$DATA_HOME/xdg-desktop-portal/portals"
XDG_PORTAL_CONFIG_DIR="$CONFIG_HOME/xdg-desktop-portal"

mkdir -p "$DBUS_SERVICE_DIR" "$XDG_PORTAL_DIR" "$XDG_PORTAL_CONFIG_DIR"

install -m 0644 \
    "$PORTAL_DIR/hyprqs.portal" \
    "$XDG_PORTAL_DIR/hyprqs.portal"
install -m 0644 \
    "$PORTAL_DIR/hyprland-portals.conf" \
    "$XDG_PORTAL_CONFIG_DIR/hyprland-portals.conf"

escaped_backend="${BACKEND//\\/\\\\}"
escaped_backend="${escaped_backend//|/\\|}"
sed "s|@BACKEND@|$escaped_backend|g" \
    "$PORTAL_DIR/org.freedesktop.impl.portal.desktop.hyprqs.service.in" \
    > "$DBUS_SERVICE_DIR/org.freedesktop.impl.portal.desktop.hyprqs.service"
chmod 0644 "$DBUS_SERVICE_DIR/org.freedesktop.impl.portal.desktop.hyprqs.service"
chmod 0755 "$BACKEND"

# dbus-broker loads activation files at login.  Reload its service index so a
# first-time install also works immediately in the current session.
gdbus call --session \
    --dest org.freedesktop.DBus \
    --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.ReloadConfig \
    >/dev/null
systemctl --user restart xdg-desktop-portal.service

printf 'Installed quickshell Wallpaper portal backend.\n'
printf 'Backend: %s\n' "$BACKEND"
