#!/usr/bin/env bash

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

apply_rules() {
    local now
    now=$(date +%s)
    (( now - COOLDOWN < 8 )) && return

    local sinks new_hash
    sinks=$(get_unavailable_sinks)
    new_hash=$(echo "$sinks" | md5sum | cut -d' ' -f1)
    [[ "$new_hash" == "$LAST_HASH" ]] && return
    LAST_HASH="$new_hash"

    if [[ -n "$sinks" ]]; then
        {
            echo "monitor.alsa.rules = ["
            local first=true
            while IFS= read -r name; do
                [[ -z "$name" ]] && continue
                $first || echo ","
                first=false
                cat <<EOL
  {
    matches = [
      { node.name = "$name" }
    ]
    actions = {
      update-props = {
        node.disabled = true
      }
    }
  }
EOL
            done <<< "$sinks"
            echo "]"
        } > "$CONF"
    else
        rm -f "$CONF"
    fi

    systemctl --user restart wireplumber
    COOLDOWN=$(date +%s)
}

rm -f "$CONF"
systemctl --user restart wireplumber
sleep 5
apply_rules

while true; do
    pactl subscribe 2>/dev/null | while read -r line; do
        if [[ "$line" == *"change"*"card"* ]] || [[ "$line" == *"new"*"sink"* ]] || [[ "$line" == *"remove"*"sink"* ]]; then
            sleep 3
            apply_rules
        fi
    done
    sleep 3
done
