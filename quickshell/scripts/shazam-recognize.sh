#!/usr/bin/env bash
# Music Recognition — identify a song and print one JSON line describing it.
# Captures a few seconds of audio, fingerprints it with songrec (an unofficial
# Shazam client), and reports the match.
#
# Usage: shazam-recognize.sh [duration] [internal|external]
#   internal (default) — the default sink's monitor: whatever the desktop is
#                        playing through the speakers.
#   external           — the default source (microphone): music playing in
#                        the room around the machine.
#
# stdout (exactly one line):
#   {"status":"ok","title":..,"artist":..,"coverart":..,"coverLocal":..,"spotify":..,"shazamUrl":..}
#   {"status":"nomatch"}
#   {"status":"error","message":..}
#
# It always exits 0 and reports problems via the JSON `status` field so the
# caller never has to interpret exit codes.
set -uo pipefail

DUR="${1:-8}"                       # seconds of audio to sample
MODE="${2:-internal}"               # internal = sink monitor, external = microphone
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/shazam"
mkdir -p "$CACHE_DIR"
WAV="$(mktemp "${TMPDIR:-/tmp}/shazam-XXXXXX.wav")"
trap 'rm -f "$WAV"' EXIT

emit_err() { printf '{"status":"error","message":%s}\n' "$(jq -Rn --arg m "$1" '$m')"; exit 0; }

command -v jq      >/dev/null 2>&1 || { echo '{"status":"error","message":"jq is not installed"}'; exit 0; }
command -v songrec >/dev/null 2>&1 || emit_err "songrec is not installed. Run: sudo pacman -S songrec"
command -v ffmpeg  >/dev/null 2>&1 || emit_err "ffmpeg is not installed"

# Pick the capture device for the requested mode.
if [ "$MODE" = "external" ]; then
    # Default source → the microphone, for music playing in the room.
    CAP="$(pactl get-default-source 2>/dev/null)"
    [ -n "$CAP" ] || emit_err "no default audio source (microphone)"
else
    # Monitor of the *current* default sink → whatever is playing right now.
    SINK="$(pactl get-default-sink 2>/dev/null)"
    [ -n "$SINK" ] || emit_err "no default audio sink"
    CAP="${SINK}.monitor"
fi

# Sample the audio into a WAV songrec can fingerprint.
if ! ffmpeg -hide_banner -loglevel error -y -f pulse -i "$CAP" \
        -t "$DUR" -ac 1 -ar 44100 "$WAV" >/dev/null 2>&1; then
    emit_err "audio capture failed"
fi

JSON="$(songrec audio-file-to-recognized-song "$WAV" 2>/dev/null)" || emit_err "recognition failed"

# No match → songrec returns an object without .track.title
TITLE="$(printf '%s' "$JSON" | jq -r '.track.title // empty' 2>/dev/null)"
if [ -z "$TITLE" ]; then
    echo '{"status":"nomatch"}'
    exit 0
fi

ARTIST="$(printf '%s' "$JSON" | jq -r '.track.subtitle // empty')"
COVER="$(printf '%s' "$JSON" | jq -r '.track.images.coverarthq // .track.images.coverart // empty')"
SHAZAM_URL="$(printf '%s' "$JSON" | jq -r '.track.url // .track.share.href // empty')"

# Link the button opens: the song's own Shazam page. It shows the track with
# links out to every streaming service and always resolves cleanly (no flaky
# search query). Fall back to a Shazam search on the rare song with no track URL.
LINK="$SHAZAM_URL"
if [ -z "$LINK" ]; then
    LINK="https://www.shazam.com/search/$(jq -rn --arg q "$TITLE $ARTIST" '$q|@uri')"
fi

# Download the cover so the desktop notification can show it as its icon
# (notify-send --icon needs a local file, not a URL).
COVER_LOCAL=""
if [ -n "$COVER" ]; then
    CANDIDATE="$CACHE_DIR/cover-$(date +%s%N).jpg"
    if curl -fsL --max-time 10 "$COVER" -o "$CANDIDATE" 2>/dev/null; then
        COVER_LOCAL="$CANDIDATE"
    fi
    # Keep the cover cache bounded to the 60 most recent files.
    ls -1t "$CACHE_DIR"/cover-* 2>/dev/null | tail -n +61 | xargs -r rm -f
fi

jq -cn \
    --arg title "$TITLE" --arg artist "$ARTIST" --arg cover "$COVER" \
    --arg coverLocal "$COVER_LOCAL" --arg link "$LINK" --arg shazam "$SHAZAM_URL" \
    '{status:"ok", title:$title, artist:$artist, coverart:$cover,
      coverLocal:$coverLocal, link:$link, shazamUrl:$shazam}'
