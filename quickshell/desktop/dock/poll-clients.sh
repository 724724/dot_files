#!/usr/bin/env bash
# Outputs: {"focused":"cls","activeWs":N,"byClass":{"cls":[{address,title,at,size,ws}...]}}
#   ws    — each window's workspace name (e.g. "1", "special:minimized"); lets the
#           dock detect Hidden windows (special:minimized) and restore them.
#   activeWs — the focused monitor's active workspace id, used to un-hide a window
#           back onto whatever workspace is currently in view.

FOCUSED=$(hyprctl activewindow -j 2>/dev/null \
    | jq -r '(.class // "") | ascii_downcase' 2>/dev/null)
FOCUSED="${FOCUSED:-}"

ACTIVE_WS=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // -1' 2>/dev/null)
[ -n "$ACTIVE_WS" ] || ACTIVE_WS=-1

BY_CLASS=$(hyprctl clients -j 2>/dev/null \
    | jq -rc '
        map(select(.class | length > 0))
        | group_by(.class | ascii_downcase)
        | map({
            key: (.[0].class | ascii_downcase),
            value: map({address, title, at, size, ws: (.workspace.name // "")})
          })
        | from_entries
    ' 2>/dev/null)
# Bash mis-parses `${BY_CLASS:-{}}` (matches the first `}` and appends the second
# as a literal), corrupting the JSON. Use an explicit empty-check instead.
[ -n "$BY_CLASS" ] || BY_CLASS='{}'

printf '{"focused":"%s","activeWs":%s,"byClass":%s}\n' "$FOCUSED" "$ACTIVE_WS" "$BY_CLASS"
