#!/usr/bin/env bash
# Outputs: {"focused":"cls","activeWs":N,"byClass":{"cls":[{address,title,class,at,size,ws,workspaceId,focusHistoryID}...]},"fullscreenMonitors":["eDP-1",...]}
#   ws    — each window's workspace name (e.g. "1", "special:minimized"); lets the
#           dock detect Hidden windows (special:minimized) and restore them.
#   activeWs — the focused monitor's active workspace id, used to un-hide a window
#           back onto whatever workspace is currently in view.
#   fullscreenMonitors — names of monitors whose active workspace currently has a
#           REAL fullscreen window (fullscreen 2 or 3; excludes maximize-only 1), so
#           the dock can auto-hide there even while pinned/always-visible.

FOCUSED=$(hyprctl activewindow -j 2>/dev/null \
    | jq -r '(.class // "") | ascii_downcase' 2>/dev/null)
FOCUSED="${FOCUSED:-}"

ACTIVE_WS=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // -1' 2>/dev/null)
[ -n "$ACTIVE_WS" ] || ACTIVE_WS=-1

CLIENTS_JSON=$(hyprctl clients -j 2>/dev/null)
[ -n "$CLIENTS_JSON" ] || CLIENTS_JSON='[]'

BY_CLASS=$(printf '%s' "$CLIENTS_JSON" | jq -rc '
        map(select(.class | length > 0))
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
    ' 2>/dev/null)
# Bash mis-parses `${BY_CLASS:-{}}` (matches the first `}` and appends the second
# as a literal), corrupting the JSON. Use an explicit empty-check instead.
[ -n "$BY_CLASS" ] || BY_CLASS='{}'

MONITORS_JSON=$(hyprctl monitors -j 2>/dev/null)
[ -n "$MONITORS_JSON" ] || MONITORS_JSON='[]'

FULLSCREEN_MONS=$(jq -cn --argjson mons "$MONITORS_JSON" --argjson clients "$CLIENTS_JSON" '
        [ $mons[] | . as $m
          | select($clients | any(
              .monitor == $m.id
              and .workspace.id == $m.activeWorkspace.id
              and ((.fullscreen // 0) >= 2)
            ))
          | $m.name
        ]
    ' 2>/dev/null)
[ -n "$FULLSCREEN_MONS" ] || FULLSCREEN_MONS='[]'

printf '{"focused":"%s","activeWs":%s,"byClass":%s,"fullscreenMonitors":%s}\n' "$FOCUSED" "$ACTIVE_WS" "$BY_CLASS" "$FULLSCREEN_MONS"
