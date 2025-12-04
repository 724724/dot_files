#!/bin/sh

# SwayNC에서 넘겨주는 토글 상태: "true" / "false"
if [ "$SWAYNC_TOGGLE_STATE" = "true" ]; then
    # 저전력 모드 ON → 항상 power-saver 프로필로
    # (AC/BAT 상관 없이 최대 절전)
    sudo tlp power-saver
else
    # 저전력 모드 OFF → TLP 자동 모드로 복귀
    # AC면 performance, BAT면 balanced 로 알아서 들어감
    sudo tlp start
fi

