#!/usr/bin/env bash
# Build one immutable, runtime-local lock configuration. Quickshell 0.3 only
# scans QML modules below an entrypoint's directory, while the lock and desktop
# remain separate named configs in the dotfiles tree. Staging the lock files
# together with the shared widget module keeps the processes independent and
# makes every current/future desktop widget visible to the lock scanner.

set -euo pipefail

if (( $# != 1 )); then
    printf 'usage: %s RUNTIME_DIRECTORY\n' "$0" >&2
    exit 2
fi

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly QUICKSHELL_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly RUNTIME_ROOT="$1"
readonly EXPECTED_ROOT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-lock"
readonly CONFIG_DIR="$RUNTIME_ROOT/config"

if [[ "$RUNTIME_ROOT" != "$EXPECTED_ROOT" ]]; then
    printf 'refusing unexpected lock runtime directory: %s\n' "$RUNTIME_ROOT" >&2
    exit 1
fi

# RuntimeDirectoryPreserve=restart deliberately keeps this snapshot after a
# crash. Never rebuild it while the compositor may already be locked: that
# would mix generations and let a bad edit break fail-closed recovery.
if [[ -r "$CONFIG_DIR/shell.qml" \
        && -r "$CONFIG_DIR/desktop/widgets/WidgetPreviewFrame.qml" ]]; then
    exit 0
fi

/usr/bin/install -d -m 0700 -- "$RUNTIME_ROOT"
readonly BUILD_DIR="$(mktemp -d "$RUNTIME_ROOT/config.new.XXXXXX")"
/usr/bin/chmod 0700 -- "$BUILD_DIR"

/usr/bin/cp -a -- "$QUICKSHELL_ROOT/lock/." "$BUILD_DIR/"
/usr/bin/install -d -m 0700 -- "$BUILD_DIR/desktop"
/usr/bin/cp -a -- "$QUICKSHELL_ROOT/desktop/widgets" "$BUILD_DIR/desktop/widgets"
/usr/bin/cp -a -- "$QUICKSHELL_ROOT/desktop/nc" "$BUILD_DIR/desktop/nc"
/usr/bin/cp -a -- "$QUICKSHELL_ROOT/desktop/icons" "$BUILD_DIR/desktop/icons"

# The service UMask is 0077. Reassert private directory permissions here for
# manual diagnostics and keep the tree atomically absent until it is complete.
/usr/bin/chmod 0700 -- "$BUILD_DIR" "$BUILD_DIR/desktop"
/usr/bin/mv -- "$BUILD_DIR" "$CONFIG_DIR"
