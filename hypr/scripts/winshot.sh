#!/usr/bin/env bash

OUT_DIR="$HOME/Pictures"
mkdir -p "$OUT_DIR"

# macOS 스타일 파일 이름
DAY="$(date +%Y-%m-%d)"
HOUR="$(date +%I)"   # 01~12
MINUTE="$(date +%M)"
SECOND="$(date +%S)"
AMP="$(date +%p)"    # AM / PM
HOUR=${HOUR#0}       # 05 -> 5

FILENAME="Screenshot $DAY at $HOUR.$MINUTE.$SECOND $AMP.png"
FINAL_PATH="$OUT_DIR/$FILENAME"

# 활성 창 geometry 가져오기
GEOM="$(hyprctl activewindow -j | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')"

# grim → magick로 그림자 + 투명 배경 처리
grim -g "$GEOM" - | magick png:- \
  \( +clone -background black -shadow 100x30+0+0 \) \
  +swap -background none -layers merge +repage \
  -alpha set \
  -strip \
  -define png:compression-level=1 \
  "$FINAL_PATH"

# 최종 결과를 클립보드로
wl-copy < "$FINAL_PATH"
notify-send -i "$FINAL_PATH" "Screenshot" "\"$FILENAME\" saved to $OUT_DIR"
