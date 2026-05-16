#!/bin/bash
# Install the SDDM brightness service + greeter-key daemon.
# Run with: sudo ./INSTALL.sh
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

DIR="$(dirname "$(readlink -f "$0")")"

install -m 0755 "$DIR/sddm-brightness-restore.sh" /usr/local/bin/sddm-brightness-restore
install -m 0755 "$DIR/sddm-brightness-keys"       /usr/local/bin/sddm-brightness-keys
install -m 0644 "$DIR/sddm-brightness-restore.service" /etc/systemd/system/sddm-brightness-restore.service
install -m 0644 "$DIR/sddm-brightness-keys.service"    /etc/systemd/system/sddm-brightness-keys.service

systemctl daemon-reload
systemctl enable sddm-brightness-restore.service
systemctl enable sddm-brightness-keys.service
# Restart (not just start) so re-installs pick up updated binaries.
systemctl restart sddm-brightness-keys.service

echo
echo "Installed. Reboot to verify brightness restore at SDDM."
echo "To uninstall: systemctl disable --now sddm-brightness-{restore,keys}.service && \\"
echo "  rm /usr/local/bin/sddm-brightness-{restore,keys} \\"
echo "     /etc/systemd/system/sddm-brightness-{restore,keys}.service && \\"
echo "  systemctl daemon-reload"
