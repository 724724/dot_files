#!/bin/sh

# 현재 TLP 상태에서 power-saver 프로필인지 검사
if tlp-stat -s 2>/dev/null | grep -q "power-saver"; then
    echo "true"
else
    echo "false"
fi

