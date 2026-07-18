#!/bin/bash
# 사용법: wallpaper.sh [이미지경로] [crop|fit|no|stretch] [padding-color]
#   인자 없이 실행하면 기본 배경(~/junk/wallpaper/wallpaper.png)을 적용한다.
#   예: wallpaper.sh ~/junk/wallpaper/1.jpeg
#
# 적용 후 GNOME picture-uri 키에도 미러한다 — quickshell(Mission Control)과
# Nautilus가 이 키를 공유하므로, 여기서 바꾸든 Nautilus에서 "배경으로 설정"을
# 하든 awww 배경과 Mission Control 배경이 함께 바뀐다.

DEFAULT_WP="/home/sejunlee/junk/wallpaper/wallpaper.png"
DEFAULT_MODE="crop"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper"

normalize_mode() {
    case "$1" in
        crop|fill|fill-screen|zoom|spanned) printf '%s\n' "crop" ;;
        fit|scale|scaled)                  printf '%s\n' "fit" ;;
        no|center|centered|none|wallpaper) printf '%s\n' "no" ;;
        stretch|stretched)                 printf '%s\n' "stretch" ;;
        *)                                 printf '%s\n' "$DEFAULT_MODE" ;;
    esac
}

gnome_option_for_mode() {
    case "$1" in
        fit)     printf '%s\n' "scaled" ;;
        no)      printf '%s\n' "centered" ;;
        stretch) printf '%s\n' "stretched" ;;
        *)       printf '%s\n' "zoom" ;;
    esac
}

normalize_color() {
    local c="$1"
    c="${c//[[:space:]]/}"

    if [[ "$c" =~ ^\#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$ ]]; then
        printf '#%s\n' "${BASH_REMATCH[1],,}"
        return
    fi

    if [[ "$c" =~ ^([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$ ]]; then
        printf '#%s\n' "${BASH_REMATCH[1],,}"
        return
    fi

    if [[ "$c" =~ ^rgba?\(([0-9]+),([0-9]+),([0-9]+)(,[0-9.]+)?\)$ ]]; then
        printf '#%02x%02x%02x\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
        return
    fi

    printf '#000000\n'
}

awww_color_for() {
    local c="$1"
    c="${c#\#}"
    printf '%sff\n' "$c"
}

convert_if_needed() {
    local src="$1"
    local ext="${src##*.}"
    local mime hash out
    ext="${ext,,}"
    mime="$(file -b --mime-type "$src" 2>/dev/null || true)"

    case "$mime:$ext" in
        image/heif:*|image/heic:*|*:heif|*:heic|*:heifs|*:heics)
            mkdir -p "$CACHE_DIR" || return 1
            hash="$(sha256sum "$src" | awk '{print $1}')"
            out="$CACHE_DIR/$hash.png"
            if [ ! -s "$out" ]; then
                if command -v magick >/dev/null 2>&1; then
                    magick "$src" -auto-orient "$out" || return 1
                elif command -v heif-convert >/dev/null 2>&1; then
                    heif-convert "$src" "$out" >/dev/null || return 1
                elif command -v ffmpeg >/dev/null 2>&1; then
                    ffmpeg -y -i "$src" -frames:v 1 "$out" >/dev/null 2>&1 || return 1
                else
                    echo "wallpaper.sh: HEIF/HEIC image requires magick, heif-convert, or ffmpeg" >&2
                    return 1
                fi
            fi
            printf '%s\n' "$out"
            ;;
        *)
            printf '%s\n' "$src"
            ;;
    esac
}

WP="$1"
if [ -n "$WP" ]; then
    WP="$(realpath "$WP" 2>/dev/null)"
    if [ -z "$WP" ] || [ ! -f "$WP" ]; then
        echo "wallpaper.sh: file not found: $1" >&2
        exit 1
    fi
    MODE="$(normalize_mode "${2:-$DEFAULT_MODE}")"
else
    # 인자 없음(부팅 시 autostart.lua 포함): 마지막으로 설정한 배경을
    # gsettings 미러(dconf에 영속)에서 읽어 복원한다. 예전처럼 기본 배경으로
    # 되돌리면 Nautilus/포털로 바꾼 배경이 재부팅마다 날아간다.
    # 미설정이거나 파일이 지워졌을 때만 기본 배경으로 폴백.
    uri=$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null | tr -d "'")
    case "$uri" in
        file://*)
            p="${uri#file://}"
            WP=$(printf '%b' "${p//%/\\x}")   # percent-decode
            ;;
    esac
    { [ -n "$WP" ] && [ -f "$WP" ]; } || WP="$DEFAULT_WP"
    opt=$(gsettings get org.gnome.desktop.background picture-options 2>/dev/null | tr -d "'")
    MODE="$(normalize_mode "$opt")"
fi
WP="$(convert_if_needed "$WP")" || exit 1
GNOME_OPT="$(gnome_option_for_mode "$MODE")"
PADDING_COLOR="$(normalize_color "${3:-$(gsettings get org.gnome.desktop.background primary-color 2>/dev/null | tr -d "'")}")"
AWWW_FILL_COLOR="$(awww_color_for "$PADDING_COLOR")"

# 데몬이 이미 실행 중인지 확인하고 없으면 실행
if ! pgrep -x "awww-daemon" > /dev/null; then
    # 데몬이 패닉으로 죽으면 소켓 파일이 남는다. 그대로 두면 다음 실행에서
    # awww가 그 소켓에 붙으려다 "connection refused"로 실패한다.
    rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/${WAYLAND_DISPLAY:-wayland-1}-awww-daemon.sock"
    # setsid + 완전 분리: 그냥 `awww-daemon &` 로 띄우면 데몬이 이 스크립트의
    # stdout/stderr(파이프)를 물려받아, 호출자가 파이프를 닫는 순간 SIGPIPE로
    # 죽는다. 부모와의 수명 결합을 끊는다.
    setsid awww-daemon >/dev/null 2>&1 </dev/null &
    # 고정 sleep 0.5는 부팅 시 짧아서, 소켓이 열리기 전에 아래 `awww img`가
    # 실행돼 배경이 아예 안 깔리는 레이스가 있었다. 준비될 때까지 폴링한다.
    for _ in $(seq 1 60); do
        awww query >/dev/null 2>&1 && break
        sleep 0.1
    done
fi

# 배경화면 설정
# [possible values: no, crop, fit, stretch]
# 특정 모니터만 지정하고 싶다면 --outputs "eDP-1" 등을 추가하면 됩니다.
awww img "$WP" --resize "$MODE" --fill-color "$AWWW_FILL_COLOR" --transition-type none

# GNOME 키 미러 (Mission Control·Nautilus 동기화). quickshell이 이 변경을
# 감지해 awww에 다시 적용하지만, 같은 이미지라 시각적 변화는 없다.
gsettings set org.gnome.desktop.background picture-uri "file://$WP" 2>/dev/null
gsettings set org.gnome.desktop.background picture-uri-dark "file://$WP" 2>/dev/null
gsettings set org.gnome.desktop.background picture-options "$GNOME_OPT" 2>/dev/null
gsettings set org.gnome.desktop.background primary-color "$PADDING_COLOR" 2>/dev/null
