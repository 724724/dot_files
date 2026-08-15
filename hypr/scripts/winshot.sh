#!/usr/bin/env bash

OUT_DIR="$HOME/Pictures"
mkdir -p "$OUT_DIR"

FILENAME="Screenshot $(date '+%Y-%m-%d at %-I.%M.%S %p').png"
FINAL_PATH="$OUT_DIR/$FILENAME"

# 화면 freeze + 커서 숨김
wayfreeze --hide-cursor &
WF_PID=$!
sleep 0.1   # 레이어 올라올 시간 조금만 줌

# grimblast가 끝나는 순간 wayfreeze 해제되도록 그룹으로 묶어서 파이프
if {
  grimblast save area - 
  kill "$WF_PID" 2>/dev/null || true
} | magick png:- \
    \( +clone -background black -shadow 100x30+0+0 \) \
    +swap -background none -layers merge +repage \
    -alpha set \
    -strip \
    -define png:compression-level=1 \
    "$FINAL_PATH"
then
  wl-copy < "$FINAL_PATH"
  (
    ACTION=$(notify-send -i "$FINAL_PATH" "Screenshot" "\"$FILENAME\" saved to $OUT_DIR" \
      --action="open=Open in Files" \
      --wait)
    
    # setsid -f로 완전히 떼어낸다. 그냥 실행하면 이 서브셸이 nautilus 창이
    # 닫힐 때까지 살아있어서, 파일 관리자를 열어둔 시간만큼 스크립트가 남는다.
    [ "$ACTION" = "open" ] && setsid -f nautilus --select "$FINAL_PATH" >/dev/null 2>&1
  ) &
fi
