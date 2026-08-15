#!/usr/bin/env bash
# Outputs: {"focused":"cls","activeWs":N,"byClass":{"cls":[{address,title,class,at,size,ws,workspaceId,focusHistoryID}...]},"fullscreenMonitors":["eDP-1",...]}
#   ws    — each window's workspace name (e.g. "1", "special:minimized"); lets the
#           dock detect Hidden windows (special:minimized) and restore them.
#   activeWs — the focused monitor's active workspace id, used to un-hide a window
#           back onto whatever workspace is currently in view.
#   fullscreenMonitors — names of monitors whose active workspace currently has a
#           REAL fullscreen window (fullscreen 2 or 3; excludes maximize-only 1), so
#           the dock can auto-hide there even while pinned/always-visible.

ACTIVE_JSON=$(hyprctl activewindow -j 2>/dev/null)
[ -n "$ACTIVE_JSON" ] || ACTIVE_JSON='{}'

WORKSPACE_JSON=$(hyprctl activeworkspace -j 2>/dev/null)
[ -n "$WORKSPACE_JSON" ] || WORKSPACE_JSON='{}'

CLIENTS_JSON=$(hyprctl clients -j 2>/dev/null)
[ -n "$CLIENTS_JSON" ] || CLIENTS_JSON='[]'

MONITORS_JSON=$(hyprctl monitors -j 2>/dev/null)
[ -n "$MONITORS_JSON" ] || MONITORS_JSON='[]'

jq -cn --argjson active "$ACTIVE_JSON" --argjson workspace "$WORKSPACE_JSON" \
    --argjson clients "$CLIENTS_JSON" --argjson mons "$MONITORS_JSON" '
    {
      focused: (($active.class // "") | ascii_downcase),
      activeWs: ($workspace.id // -1),
      byClass: (
        $clients
        | map(select(.class | length > 0))
        | group_by(.class | ascii_downcase)
        | map({
            key: (.[0].class | ascii_downcase),
            value: map({
              address,
              title,
              class,
              at,
              size,
              ws: (.workspace.name // ""),
              workspaceId: (.workspace.id // -1),
              focusHistoryID: (.focusHistoryID // 999999)
            })
          })
        | from_entries
      ),
      fullscreenMonitors: [
        $mons[] | . as $m
        | select($clients | any(
            .monitor == $m.id
            and .workspace.id == $m.activeWorkspace.id
            and ((.fullscreen // 0) >= 2)
          ))
        | $m.name
      ]
    }
' 2>/dev/null || printf '{"focused":"","activeWs":-1,"byClass":{},"fullscreenMonitors":[]}\n'
