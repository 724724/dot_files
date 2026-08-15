#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SOURCE_DIR="$(cd -- "$SCRIPT_DIR/../../pam" && pwd)"
readonly TARGET_DIR="/etc/pam.d"

printf '%s\n' 'Quickshell lock용 PAM 정책 두 개를 root 소유로 설치합니다.'
printf '%s\n' 'sudo 비밀번호는 이 터미널에만 입력하세요.'

sudo /usr/bin/install -o root -g root -m 0644 \
    "$SOURCE_DIR/quickshell-lock-password" \
    "$SOURCE_DIR/quickshell-lock-fingerprint" \
    "$TARGET_DIR/"

/usr/bin/stat -c '%a %U:%G %F %n' \
    "$TARGET_DIR/quickshell-lock-password" \
    "$TARGET_DIR/quickshell-lock-fingerprint"

printf '%s\n' '설치 완료. 이 창을 닫아도 됩니다.'
