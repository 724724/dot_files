#!/bin/bash
set -euo pipefail

systemctl --user disable --now quickshell-camera-effects.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/quickshell-camera-effects.service"
systemctl --user daemon-reload

if grep -q '^v4l2loopback ' /proc/modules; then
    if ! sudo modprobe -r v4l2loopback; then
        echo "Close every camera application, then run this script again." >&2
        exit 1
    fi
fi

sudo rm -f /etc/modprobe.d/quickshell-v4l2loopback.conf
sudo rm -f /etc/modules-load.d/quickshell-v4l2loopback.conf

packages=()
for package in v4l2loopback-dkms v4l2loopback-utils; do
    if pacman -Q "$package" >/dev/null 2>&1; then
        packages+=("$package")
    fi
done

if ((${#packages[@]})); then
    sudo pacman -Rns -- "${packages[@]}"
fi
