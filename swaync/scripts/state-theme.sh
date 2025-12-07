#!/usr/bin/env bash

# color-scheme 기준으로 토글 상태 표시 (swaync 에서는 true/false만 필요)
SCHEME="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo "'default'")"

case "$SCHEME" in
    *dark*)
        echo true   # 다크 모드일 때 토글 ON
        ;;
    *)
        echo false  # 라이트 모드일 때 토글 OFF
        ;;
esac

exit 0

