#!/usr/bin/env bash
# Prepare user-writable browser policy directories used by focus-sites.sh.

set -euo pipefail

readonly USER_NAME="$(/usr/bin/id -un)"
readonly USER_GROUP="$(/usr/bin/id -gn)"
readonly FIREFOX_POLICY_DIR="/etc/firefox/policies"
readonly CHROMIUM_POLICY_DIR="/etc/opt/chrome/policies/managed"

ensure_policy_dir() {
    local path="$1"

    if [[ -e "$path" && ! -d "$path" ]]; then
        printf 'Refusing to replace non-directory policy path: %s\n' "$path" >&2
        return 1
    fi

    if [[ -d "$path" ]]; then
        if [[ ! -w "$path" ]]; then
            printf 'Existing policy directory is administrator-managed: %s\n' "$path" >&2
            printf '%s\n' 'Ownership was not changed; review it manually.' >&2
            return 1
        fi
        printf 'Policy directory already ready: %s\n' "$path"
        return 0
    fi

    /usr/bin/sudo /usr/bin/install -d -o "$USER_NAME" -g "$USER_GROUP" \
        -m 0755 -- "$path"
    printf 'Created policy directory: %s\n' "$path"
}

ensure_policy_dir "$FIREFOX_POLICY_DIR"
ensure_policy_dir "$CHROMIUM_POLICY_DIR"

printf '%s\n' 'Focus-mode browser policy setup complete.'
