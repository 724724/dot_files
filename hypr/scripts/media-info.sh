#!/bin/bash
# Outputs JSON with the currently active player's status/title/artist/artUrl.
# Routes through playerctld so the most-recently-active player is always picked.
#
# Also reports `artDark` — whether the album art is overall dark — so the bar
# can flip the overlaid text white/black for legibility (iOS-style). The
# brightness probe is cached per art URL so it only runs once per track, not on
# every 1.5s poll.

PC="playerctl --player=playerctld"

META=$($PC metadata --format $'{{status}}\x1f{{title}}\x1f{{artist}}\x1f{{mpris:artUrl}}' 2>/dev/null)
STATUS=${META%%$'\x1f'*}
META=${META#*$'\x1f'}
TITLE=${META%%$'\x1f'*}
META=${META#*$'\x1f'}
ARTIST=${META%%$'\x1f'*}
ART=${META#*$'\x1f'}
if [ -z "$STATUS" ] || [ "$STATUS" = "Stopped" ]; then
    printf '{"status":"none","title":"","artist":"","artUrl":"","artDark":true}\n'
    exit 0
fi

# ── Album-art brightness probe (cached by URL) ───────────────────────────────
# Default to "dark" so unknown art shows white text (the safer default).
ARTDARK=true
ARTACCENT=""
CACHE="/tmp/qs-media-art.cache"   # line1: art URL  line2: true|false  line3: #accent
IMG="/tmp/qs-media-art.img"       # downloaded copy for remote art

if [ -n "$ART" ]; then
    CACHED=()
    [[ -r "$CACHE" ]] && mapfile -t CACHED < "$CACHE"
    CACHED_URL="${CACHED[0]:-}"
    if [ "$CACHED_URL" = "$ART" ]; then
        # Same track as last probe — reuse the cached result.
        CACHED_DARK="${CACHED[1]:-}"
        [ -n "$CACHED_DARK" ] && ARTDARK="$CACHED_DARK"
        ARTACCENT="${CACHED[2]:-}"
    else
        # Resolve the art to a local path (download remote art once).
        SRC=""
        case "$ART" in
            file://*)
                # Strip scheme and percent-decode the path.
                P="${ART#file://}"
                SRC=$(printf '%b' "${P//%/\\x}")
                ;;
            http://*|https://*)
                if curl -sL --max-time 4 -o "$IMG" "$ART" 2>/dev/null; then
                    SRC="$IMG"
                fi
                ;;
            *)
                SRC="$ART"
                ;;
        esac

        if [ -n "$SRC" ] && [ -f "$SRC" ]; then
            MEAN=$(magick "$SRC" -resize 64x64 -colorspace Gray \
                   -format '%[fx:mean]' info: 2>/dev/null)
            if [ -n "$MEAN" ]; then
                # mean is 0..1. The bar shows a near-opaque, heavily blurred
                # cover, so the pill brightness ≈ this mean. < 0.55 → dark pill
                # → white text; otherwise bright pill → black text.
                if awk -v m="$MEAN" 'BEGIN{exit !(m < 0.55)}'; then
                    ARTDARK=true
                else
                    ARTDARK=false
                fi
            fi
            # Most vivid colour in the cover, for the bar's EQ bars. Quantize to
            # 8 colours, then pick the one with the best saturation/among
            # mid-brightness candidates (avoids near-black/near-white picks).
            ARTACCENT=$(magick "$SRC" -resize 64x64 -colors 8 -depth 8 \
                        -format %c histogram:info:- 2>/dev/null \
                | python3 "$HOME/.config/quickshell/scripts/album-accent.py" 2>/dev/null)
        fi
        printf '%s\n%s\n%s\n' "$ART" "$ARTDARK" "$ARTACCENT" > "$CACHE"
    fi
fi

# Use jq to JSON-encode safely (handles quotes, backslashes, unicode).
jq -nc --arg s "$STATUS" --arg t "$TITLE" --arg a "$ARTIST" --arg u "$ART" \
       --arg c "$ARTACCENT" --argjson d "$ARTDARK" \
    '{status:$s, title:$t, artist:$a, artUrl:$u, artDark:$d, artAccent:$c}'
