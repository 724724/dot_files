#!/usr/bin/env bash

MODE="$1"              # output, region, window 등
OUT_DIR="$HOME/Pictures"

DAY="$(date +%Y-%m-%d)"
HOUR="$(date +%I)"     # 01~12
MINUTE="$(date +%M)"
SECOND="$(date +%S)"
AMP="$(date +%p)"      # AM / PM
HOUR=${HOUR#0}         # 앞 0 제거 → 05 -> 5

FILENAME="Screenshot $DAY at $HOUR.$MINUTE.$SECOND $AMP.png"

hyprshot -m "$MODE" -o "$OUT_DIR" -f "$FILENAME"
