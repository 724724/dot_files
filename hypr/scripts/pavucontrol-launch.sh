#!/bin/bash
# Smart pavucontrol opener:
#   - If an instance is already running, move its window to the current
#     workspace and focus it (instant).
#   - Otherwise spawn a fresh instance pinned to the current workspace.

WS=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id')
ADDR=$(hyprctl clients -j 2>/dev/null \
    | jq -r '[.[] | select(.class=="org.pulseaudio.pavucontrol")] | first | .address // empty')

if [ -n "$ADDR" ]; then
    hyprctl eval "hl.dispatch(hl.dsp.window.move({ workspace = $WS, window = \"address:$ADDR\" })); hl.dispatch(hl.dsp.focus({ window = \"address:$ADDR\" }))" >/dev/null
else
    hyprctl dispatch "hl.dsp.exec_cmd(\"pavucontrol\", { workspace = \"$WS\" })" >/dev/null
fi
