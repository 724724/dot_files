#!/usr/bin/env bash
# Browser site allowlist for Pomodoro focus sessions.
#
#   focus-sites.sh apply <site>...   restrict browsers to those sites only
#   focus-sites.sh clear             remove the restriction
#
# Called by ClockService._recomputeFocus() whenever the focus state changes.
# Sites are bare hosts as typed by the user ("instagram.com"); subdomains are
# included automatically.
#
# Browsers only read these policy files at STARTUP, so a running browser has to
# be restarted for a change to take effect — the shell closes allowed browsers
# when a restricted session starts for exactly that reason.
#
# One-time setup (root once, then never again):
#   ~/.config/quickshell/scripts/installs/install-focus-sites.sh
#
# Fail-safe: `clear` is also run at shell startup, so a crash mid-session can
# never leave a browser locked behind a stale allowlist.

set -u

FF_DIR=/etc/firefox/policies
FF_FILE="$FF_DIR/policies.json"
FF_MARK="$FF_DIR/.qs-focus-owned"
CR_DIR=/etc/opt/chrome/policies/managed
CR_FILE="$CR_DIR/qs-focus.json"

action="${1:-}"
shift || true

notify() { command -v notify-send >/dev/null 2>&1 && notify-send -a Focus "$@"; }

# Strip scheme / path / port / leading www., lowercase. "https://www.x.com/a" -> "x.com"
normalize() {
    local s="$1"
    s="${s#*://}"
    s="${s%%/*}"
    s="${s%%:*}"
    s="${s##www.}"
    printf '%s' "$s" | tr '[:upper:]' '[:lower:]'
}

clear_firefox() {
    # Only ever remove a policies.json we wrote ourselves.
    [ -e "$FF_MARK" ] || return 0
    rm -f "$FF_FILE" "$FF_MARK" 2>/dev/null
}

clear_chrome() {
    [ -e "$CR_FILE" ] && rm -f "$CR_FILE" 2>/dev/null
    return 0
}

if [ "$action" = "clear" ]; then
    clear_firefox
    clear_chrome
    exit 0
fi

[ "$action" = "apply" ] || { echo "usage: $0 apply <site>... | clear" >&2; exit 2; }

# Collect + normalize the requested hosts.
hosts=()
for raw in "$@"; do
    h="$(normalize "$raw")"
    [ -n "$h" ] && hosts+=("$h")
done
# Nothing to restrict to → same as clear (a browser with no site list stays open).
if [ "${#hosts[@]}" -eq 0 ]; then
    clear_firefox
    clear_chrome
    exit 0
fi

# ── Firefox: WebsiteFilter (block everything, allow the listed hosts) ────────
if [ -d "$FF_DIR" ] && [ -w "$FF_DIR" ]; then
    if [ -e "$FF_FILE" ] && [ ! -e "$FF_MARK" ]; then
        notify "Focus Mode" "An existing Firefox policy is in place — site limits skipped."
    else
        # Two patterns per host so both the bare domain and its subdomains match.
        if printf '%s\n' "${hosts[@]}" | jq -R . | jq -s \
            '{policies:{WebsiteFilter:{Block:["<all_urls>"],
              Exceptions:( map("*://\(.)/*", "*://*.\(.)/*") )}}}' > "$FF_FILE".tmp 2>/dev/null
        then
            mv "$FF_FILE".tmp "$FF_FILE" && : > "$FF_MARK"
        else
            rm -f "$FF_FILE".tmp
            notify "Focus Mode" "Could not write the Firefox site policy."
        fi
    fi
elif [ -d /usr/lib/firefox ]; then
    notify "Focus Mode" "Site limits need setup: run scripts/installs/install-focus-sites.sh"
fi

# ── Chrome/Chromium: URLBlocklist + URLAllowlist (only if set up) ────────────
if [ -d "$CR_DIR" ] && [ -w "$CR_DIR" ]; then
    printf '%s\n' "${hosts[@]}" | jq -R . | jq -s \
        '{URLBlocklist:["*"],URLAllowlist:.}' > "$CR_FILE".tmp 2>/dev/null \
        && mv "$CR_FILE".tmp "$CR_FILE" || rm -f "$CR_FILE".tmp
fi

exit 0
