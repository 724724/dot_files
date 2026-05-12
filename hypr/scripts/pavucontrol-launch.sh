#!/bin/bash
# Smart pavucontrol opener:
#   - If an instance is already running, move its window to the current
#     workspace and focus it (instant).
#   - Otherwise spawn a fresh instance pinned to the current workspace.

WS=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id')
ADDR=$(hyprctl clients -j 2>/dev/null \
    | jq -r '[.[] | select(.class=="org.pulseaudio.pavucontrol")] | first | .address // empty')

if [ -n "$ADDR" ]; then
    hyprctl --batch "dispatch movetoworkspace $WS,address:$ADDR ; dispatch focuswindow address:$ADDR" >/dev/null
else
    hyprctl dispatch exec "[workspace $WS] pavucontrol" >/dev/null
fi
