#!/usr/bin/env bash
# Outputs: {"focused":"classname","byClass":{"cls":[{address,title,at,size}...]}}

FOCUSED=$(hyprctl activewindow -j 2>/dev/null \
    | jq -r '(.class // "") | ascii_downcase' 2>/dev/null)
FOCUSED="${FOCUSED:-}"

BY_CLASS=$(hyprctl clients -j 2>/dev/null \
    | jq -rc '
        map(select(.class | length > 0))
        | group_by(.class | ascii_downcase)
        | map({
            key: (.[0].class | ascii_downcase),
            value: map({address, title, at, size})
          })
        | from_entries
    ' 2>/dev/null)
# Bash mis-parses `${BY_CLASS:-{}}` (matches the first `}` and appends the second
# as a literal), corrupting the JSON. Use an explicit empty-check instead.
[ -n "$BY_CLASS" ] || BY_CLASS='{}'

printf '{"focused":"%s","byClass":%s}\n' "$FOCUSED" "$BY_CLASS"
