#!/usr/bin/env bash
STATE=$(hyprctl monitors -j | jq -r '.[0].dpmsStatus')
if [ "$STATE" = "true" ]; then
    hyprctl dispatch dpms off
else
    hyprctl dispatch dpms on
fi
