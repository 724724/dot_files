#!/usr/bin/env bash
# openmeteo-fetch.sh <url> — curl an open-meteo URL with a routing fallback.
#
# Some ISPs (this one included) can't reach api.open-meteo.com's only A record
# (188.40.99.226): TCP connects but the TLS handshake times out. The identical
# API answers on open-meteo's other hosts (wildcard *.open-meteo.com cert), so
# on failure re-pin api.open-meteo.com to those hosts' IPs via --resolve.
# Direct is always tried first, so nothing changes when routing is healthy.
url="$1"
[ -n "$url" ] || exit 2

out=$(curl -sf --max-time 8 "$url") && { printf '%s' "$out"; exit 0; }

# Fallback only applies to the forecast host; geocoding-api etc. resolve to
# different, reachable IPs and their API isn't served by these mirrors.
case "$url" in
    https://api.open-meteo.com/*) ;;
    *) exit 1 ;;
esac

for h in archive-api.open-meteo.com customer-api.open-meteo.com; do
    ip=$(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1; exit}')
    [ -n "$ip" ] || continue
    out=$(curl -sf --max-time 8 --resolve "api.open-meteo.com:443:$ip" "$url") \
        && { printf '%s' "$out"; exit 0; }
done
exit 1
