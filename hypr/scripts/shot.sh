#!/usr/bin/env bash

MODE="$1"              # output, region
OUT_DIR="$HOME/Pictures"
mkdir -p "$OUT_DIR"

FILENAME="Screenshot $(date '+%Y-%m-%d at %-I.%M.%S %p').png"
TARGET="$OUT_DIR/$FILENAME"

case "$MODE" in
  output)
    # 현재 모니터 전체: 저장 + 클립보드
    grimblast copysave output "$TARGET"
    ;;
  region|area)
    # 영역 선택(창/직사각형 선택 가능) + freeze + 저장 + 클립보드
    grimblast -f copysave area "$TARGET"
    ;;
  *)
    echo "Usage: $0 {output|region}" >&2
    exit 1
    ;;
esac

# 파일이 실제로 존재할 때만 알림 전송
# grimblast는 ESC로 취소하면 파일을 생성하지 않고 종료 코드 1을 반환합니다.
if [ -f "$TARGET" ]; then
  (
    ACTION=$(notify-send -i "$TARGET" "Screenshot" "\"$FILENAME\" saved to $OUT_DIR" \
      --action="open=Open in Files" \
      --wait)
    
    # setsid -f로 완전히 떼어낸다. 그냥 실행하면 이 서브셸이 nautilus 창이
    # 닫힐 때까지 살아있어서, 파일 관리자를 열어둔 시간만큼 스크립트가 남는다.
    [ "$ACTION" = "open" ] && setsid -f nautilus --select "$TARGET" >/dev/null 2>&1
  ) &
fi
