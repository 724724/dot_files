#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE="quickshell-stock-worker.service"
TIMER="quickshell-stock-worker.timer"
ACTION="${1:-install}"

install_worker() {
    install -Dm644 "$ROOT/systemd/user/$SERVICE" "$UNIT_DIR/$SERVICE"
    install -Dm644 "$ROOT/systemd/user/$TIMER" "$UNIT_DIR/$TIMER"
    systemctl --user daemon-reload
    systemctl --user enable --now "$TIMER"
    systemctl --user start --no-block "$SERVICE"
    systemctl --user --no-pager status "$TIMER"
}

remove_worker() {
    systemctl --user disable --now "$TIMER" 2>/dev/null || true
    systemctl --user stop "$SERVICE" 2>/dev/null || true
    rm -f "$UNIT_DIR/$SERVICE" "$UNIT_DIR/$TIMER"
    systemctl --user daemon-reload
    systemctl --user reset-failed
}

case "$ACTION" in
    install) install_worker ;;
    uninstall) remove_worker ;;
    status) systemctl --user --no-pager status "$TIMER" "$SERVICE" ;;
    run) python3 "$ROOT/scripts/stock-service.py" background run ;;
    *) echo "usage: $0 {install|uninstall|status|run}" >&2; exit 2 ;;
esac
