#!/usr/bin/env bash
# hide-unplugged-sinks.sh
# Monitors audio card changes and hides unavailable (unplugged) sinks
# via WirePlumber rules so they don't clutter pavucontrol.

CONF="$HOME/.config/wireplumber/wireplumber.conf.d/disable-unplugged.conf"
mkdir -p "$(dirname "$CONF")"

LAST_HASH=""
COOLDOWN=0
BASE="alsa_output.pci-0000_00_1f.3-platform-sof_sdw.HiFi__"

get_unavailable_sinks() {
    pactl list cards 2>/dev/null \
        | grep -E '^\s+\[Out\].*not available\)' \
        | sed -E 's/.*\[Out\] ([^:]+):.*/\1/' \
        | while read -r port; do
            echo "${BASE}${port}__sink"
        done
}

generate_conf() {
    local sinks=("$@")
    echo "monitor.alsa.rules = ["
    for i in "${!sinks[@]}"; do
        [[ -z "${sinks[$i]}" ]] && continue
        cat <<EOF
  {
    matches = [
      { node.name = "${sinks[$i]}" }
    ]
    actions = {
      update-props = {
        node.disabled = true
      }
    }
  }
EOF
    done
    echo "]"
}

apply_rules() {
    local now
    now=$(date +%s)
    (( now - COOLDOWN < 8 )) && return

    local new_hash
    mapfile -t sinks < <(get_unavailable_sinks)
    new_hash=$(printf '%s\n' "${sinks[@]}" | md5sum | cut -d' ' -f1)
    [[ "$new_hash" == "$LAST_HASH" ]] && return
    LAST_HASH="$new_hash"

    if [[ ${#sinks[@]} -gt 0 && -n "${sinks[0]}" ]]; then
        generate_conf "${sinks[@]}" > "$CONF"
    else
        rm -f "$CONF"
    fi

    systemctl --user restart wireplumber
    COOLDOWN=$(date +%s)
}

cleanup() {
    rm -f "$CONF"
    systemctl --user restart wireplumber
    exit 0
}
trap cleanup EXIT INT TERM

# Initial clean state
rm -f "$CONF"
systemctl --user restart wireplumber
sleep 5
apply_rules

# Watch for card/sink changes
while true; do
    pactl subscribe 2>/dev/null | while read -r line; do
        case "$line" in
            *"change"*"card"*|*"new"*"sink"*|*"remove"*"sink"*)
                sleep 3
                apply_rules
                ;;
        esac
    done
    sleep 3
done
