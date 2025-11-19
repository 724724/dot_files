#!/usr/bin/env bash

OUT_DIR="$HOME/Pictures"
mkdir -p "$OUT_DIR"

DAY="$(date +%Y-%m-%d)"
HOUR="$(date +%I)"   # 01~12
MINUTE="$(date +%M)"
SECOND="$(date +%S)"
AMP="$(date +%p)"    # AM / PM
HOUR=${HOUR#0}       # 앞 0 제거

FILENAME="Screenshot $DAY at $HOUR.$MINUTE.$SECOND $AMP.png"
FINAL_PATH="$OUT_DIR/$FILENAME"

hyprshot -m window --raw | magick png:- \
  \( +clone -background black -shadow 100x30+0+0 \) \
  +swap -background white -layers merge +repage \
  -strip \
  -define png:compression-level=1 \
  "$FINAL_PATH"

wl-copy < "$FINAL_PATH"
