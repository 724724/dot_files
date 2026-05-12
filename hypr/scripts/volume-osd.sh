#!/bin/bash
# Usage: volume-osd.sh 5%+ | 5%- | 2%+ | 2%-
# -l 1 limits volume to 100%
wpctl set-volume @DEFAULT_AUDIO_SINK@ "$1" -l 1

VOL=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "%d", $2 * 100}')
qs ipc -c desktop call osd volume "$VOL"
