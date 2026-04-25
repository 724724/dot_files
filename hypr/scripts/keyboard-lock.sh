#!/bin/bash
# ~/.config/hypr/scripts/keyboard-lock.sh

current=$(hyprctl activewindow -j | jq -r '.submap // empty' 2>/dev/null)
submap=$(hyprctl getoption general:allow_tearing -j 2>/dev/null)

# submap 상태 확인
state=$(hyprctl monitors -j | jq -r '.[0].activeWorkspace.name' 2>/dev/null)
