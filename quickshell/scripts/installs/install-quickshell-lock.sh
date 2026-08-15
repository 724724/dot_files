#!/usr/bin/env bash
# Install the machine-local pieces of the standalone Quickshell session lock.
# The QML and helper scripts remain in the user's dotfiles; only the root-owned
# PAM policies and the user systemd unit are copied into their native locations.

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly QUICKSHELL_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
readonly UNIT_SOURCE="$QUICKSHELL_ROOT/systemd/user/quickshell-lock.service"
readonly STAGE_SCRIPT="$QUICKSHELL_ROOT/scripts/quickshell-lock-stage.sh"
readonly BLUR_SCRIPT="$QUICKSHELL_ROOT/scripts/quickshell-lock-blur.sh"
readonly UNIT_DIR="$HOME/.config/systemd/user"
readonly UNIT_TARGET="$UNIT_DIR/quickshell-lock.service"

missing=()
for command_name in qs systemctl systemd-analyze grim magick jq playerctl \
        python3 setpriv pactl parec; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        missing+=("$command_name")
    fi
done

if (( ${#missing[@]} > 0 )); then
    printf 'Missing lock dependencies: %s\n' "${missing[*]}" >&2
    exit 1
fi

if [[ ! -x "$STAGE_SCRIPT" ]]; then
    printf 'Lock staging helper is not executable: %s\n' "$STAGE_SCRIPT" >&2
    exit 1
fi

if [[ ! -x "$BLUR_SCRIPT" ]]; then
    printf 'Lock blur helper is not executable: %s\n' "$BLUR_SCRIPT" >&2
    exit 1
fi

if systemctl --user is-active --quiet quickshell-lock.service; then
    printf '%s\n' 'Unlock the current session before reinstalling the lock service.' >&2
    exit 1
fi

/usr/bin/install -d -m 0700 -- "$UNIT_DIR"
/usr/bin/install -m 0644 -- "$UNIT_SOURCE" "$UNIT_TARGET"
"$SCRIPT_DIR/install-quickshell-lock-pam.sh"

systemctl --user daemon-reload
systemd-analyze --user verify "$UNIT_TARGET"

printf '%s\n' 'Quickshell lock installation complete.'
printf '%s\n' 'The service is intentionally static/on-demand; do not enable it.'
printf '%s\n' 'Test with: ~/.config/quickshell/scripts/quickshell-lock.sh lock'
