#!/usr/bin/env bash
# Hide unavailable UCM outputs/inputs without hard-coding this laptop's card.
# `pactl subscribe` sleeps in the server while idle; rules are regenerated only
# after an audio topology event, and WirePlumber is restarted only when the
# resulting configuration actually changed.

set -u

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CONF="$CONFIG_HOME/wireplumber/wireplumber.conf.d/disable-unplugged.conf"
mkdir -p "$(dirname "$CONF")"

# snd-aloop's "Loopback" card (ALSA card 0) is loaded at boot by
# /etc/modules-load.d/droidcam.conf so DroidCam can feed the phone's microphone
# in as a capture device. It is the transport for DroidCam *audio* only —
# DroidCam video rides v4l2loopback-dc and never touches this.
#
# It is hidden while DroidCam is not running (idle, it just clutters the picker
# with a sink, a source and a monitor all called "Loopback Analog Stereo") and
# unhidden automatically as soon as DroidCam starts, so the phone mic is
# selectable without anyone editing a file.
#
# Listed as a constant instead of being discovered from `pactl list cards`,
# unlike everything else here: device.disabled removes the card from that
# listing too, so a derived rule would delete itself on the next regeneration
# and the device would flap straight back into view.
VIRTUAL_CARDS=(
    "alsa_card.platform-snd_aloop.0"
)

# Interval for the "is DroidCam up?" re-check. Topology changes still arrive
# immediately over `pactl subscribe`; this only covers DroidCam starting, which
# produces no PipeWire event at all while the card is disabled.
POLL_SECS=4

# The process check is the primary signal because the loopback has to be
# *selectable* before audio flows — waiting for the PCM to open would mean the
# source only appears after the user already needed it. The PCM check is a
# fallback for anything else driving the loopback directly (arecord, a script).
droidcam_active() {
    pgrep -x 'droidcam(-cli)?' >/dev/null 2>&1 && return 0
    local st state
    for st in /proc/asound/Loopback/pcm*/sub0/status; do
        [[ -r $st ]] || continue
        IFS= read -r state < "$st" 2>/dev/null || state=""
        [[ $state == closed ]] || return 0
    done
    return 1
}

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

get_internal_cards() {
    local line card

    while IFS= read -r line; do
        if [[ $line =~ Name:[[:space:]]+alsa_card\.(.+)$ ]]; then
            card="${BASH_REMATCH[1]}"
            # On-board controllers enumerate on PCI. USB and Bluetooth devices
            # ship a usable description of their own ("EarPods"), so they are
            # left alone.
            [[ $card == pci-* ]] && printf 'alsa_card.%s\n' "$card"
        fi
    done < <(pactl list cards 2>/dev/null)
}

generate_conf() {
    local node card
    printf 'monitor.alsa.rules = [\n'
    # Every port inherits its card's device.description, which ALSA reports for
    # the on-board controller as e.g. "Core Ultra 200H/200V Series Processors HD
    # Audio". That prefix fills the whole line in the output picker, so Speaker,
    # Headphones and HDMI all render identically and cannot be told apart.
    # Renaming the card once fixes every port it owns, including ports that only
    # show up later, which is why this is not a per-sink node.description.
    while IFS= read -r card; do
        [[ -n $card ]] || continue
        cat <<EOF
  {
    matches = [
      { device.name = "$card" }
    ]
    actions = {
      update-props = {
        device.description = "Built-in Audio"
      }
    }
  }
EOF
    done < <(get_internal_cards | sort -u)
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
    # Suppressed only while DroidCam is down; the closing bracket below must be
    # emitted either way, so this gates the loop rather than returning early.
    local vcard
    if ! droidcam_active; then
        for vcard in ${VIRTUAL_CARDS[@]+"${VIRTUAL_CARDS[@]}"}; do
            cat <<EOF
  {
    matches = [
      { device.name = "$vcard" }
    ]
    actions = {
      update-props = {
        device.disabled = true
      }
    }
  }
EOF
        done
    fi
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

if droidcam_active; then droidcam_was=y; else droidcam_was=n; fi

while true; do
    while true; do
        IFS= read -r -t "$POLL_SECS" line
        rc=$?
        if (( rc == 0 )); then
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
        elif (( rc > 128 )); then
            # read timed out. Starting DroidCam moves no PipeWire node while the
            # loopback is disabled, so it raises no subscribe event — this is the
            # only thing that notices. Regenerating costs two `pactl list cards`
            # calls, so gate it on the flag actually flipping; the steady-state
            # cost of this branch is one pgrep.
            if droidcam_active; then droidcam_now=y; else droidcam_now=n; fi
            if [[ $droidcam_now != "$droidcam_was" ]]; then
                droidcam_was=$droidcam_now
                apply_rules
            fi
        else
            break   # pactl subscribe exited; fall through to the restart sleep
        fi
    done < <(pactl subscribe 2>/dev/null)
    sleep 3
done
