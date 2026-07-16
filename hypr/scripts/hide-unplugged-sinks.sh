#!/usr/bin/env bash
# Hide unavailable UCM outputs/inputs without hard-coding this laptop's card.
# `pactl subscribe` sleeps in the server while idle; rules are regenerated only
# after an audio topology event, and WirePlumber is restarted only when the
# resulting configuration actually changed.

set -u

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CONF="$CONFIG_HOME/wireplumber/wireplumber.conf.d/disable-unplugged.conf"
mkdir -p "$(dirname "$CONF")"

get_unavailable_nodes() {
    local card="" line direction port prefix suffix

    while IFS= read -r line; do
        if [[ $line =~ Name:[[:space:]]+alsa_card\.(.+)$ ]]; then
            card="${BASH_REMATCH[1]}"
            continue
        fi
        [[ -n $card ]] || continue
        if [[ $line =~ \[(Out|In)\][[:space:]]+([^:]+):.*not[[:space:]]available\) ]]; then
            direction="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[2]}"
            if [[ $direction == Out ]]; then
                prefix="alsa_output"
                suffix="sink"
            else
                prefix="alsa_input"
                suffix="source"
            fi
            printf '%s.%s.HiFi__%s__%s\n' "$prefix" "$card" "$port" "$suffix"
        fi
    done < <(pactl list cards 2>/dev/null)
}

generate_conf() {
    local node
    printf 'monitor.alsa.rules = [\n'
    while IFS= read -r node; do
        [[ -n $node ]] || continue
        cat <<EOF
  {
    matches = [
      { node.name = "$node" }
    ]
    actions = {
      update-props = {
        node.disabled = true
      }
    }
  }
EOF
    done < <(get_unavailable_nodes | sort -u)
    printf ']\n'
}

apply_rules() {
    local tmp
    tmp=$(mktemp "${CONF}.XXXXXX") || return
    generate_conf > "$tmp"

    if [[ -f $CONF ]] && cmp -s "$tmp" "$CONF"; then
        rm -f "$tmp"
        return
    fi

    chmod 0644 "$tmp"
    mv -f "$tmp" "$CONF"
    systemctl --user restart wireplumber
}

case "${1:-}" in
    --print)
        generate_conf
        exit
        ;;
    --once)
        apply_rules
        exit
        ;;
esac

apply_rules

while true; do
    while IFS= read -r line; do
        case "$line" in
            *"change"*"card"*|*"new"*"card"*|*"remove"*"card"*|\
            *"new"*"sink"*|*"remove"*"sink"*|\
            *"new"*"source"*|*"remove"*"source"*)
                # Let WirePlumber finish the topology burst, then compare the
                # complete generated file. Repeated identical events are free.
                sleep 1
                apply_rules
                ;;
        esac
    done < <(pactl subscribe 2>/dev/null)
    sleep 3
done
