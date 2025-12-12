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

# 화면 freeze + 커서 숨김
wayfreeze --hide-cursor &
WF_PID=$!
sleep 0.1   # 레이어 올라올 시간 조금만 줌

# grimblast가 끝나는 순간 wayfreeze 해제되도록 그룹으로 묶어서 파이프
if { 
  grimblast save area -   # 영역 선택 후 PNG를 stdout으로
  kill "$WF_PID" 2>/dev/null || true   # grimblast 끝난 직후 freeze 해제
} | magick png:- \
    \( +clone -background black -shadow 100x30+0+0 \) \
    +swap -background none -layers merge +repage \
    -alpha set \
    -strip \
    -define png:compression-level=1 \
    "$FINAL_PATH"
then
  wl-copy < "$FINAL_PATH"
  notify-send -i "$FINAL_PATH" "Screenshot" "\"$FILENAME\" saved to $OUT_DIR"
fi

