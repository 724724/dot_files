#!/usr/bin/env bash
# Rofi script modi: Web Search (Google + YouTube)

ICON_DIR="$HOME/.config/rofi/icons"

urlencode() {
    python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1" 2>/dev/null \
        || echo "$1" | sed 's/ /+/g'
}

if [ "$ROFI_RETV" = "0" ]; then
    echo -en "\0no-custom\x1ffalse\n"

elif [ "$ROFI_RETV" = "2" ]; then
    echo -en "\0data\x1f${1}\n"
    echo -en "\0no-custom\x1ffalse\n"
    echo -e "Search '${1}' on Google\0icon\x1f${ICON_DIR}/google.svg\x1finfo\x1fgoogle"
    echo -e "Search '${1}' on YouTube\0icon\x1f${ICON_DIR}/youtube.svg\x1finfo\x1fyoutube"

elif [ "$ROFI_RETV" = "1" ]; then
    if [ "$ROFI_INFO" = "google" ]; then
        q=$(urlencode "$ROFI_DATA")
        xdg-open "https://www.google.com/search?q=${q}" &>/dev/null &
        exit 0
    elif [ "$ROFI_INFO" = "youtube" ]; then
        q=$(urlencode "$ROFI_DATA")
        xdg-open "https://www.youtube.com/results?search_query=${q}" &>/dev/null &
        exit 0
    else
        echo -en "\0data\x1f${1}\n"
        echo -en "\0no-custom\x1ffalse\n"
        echo -e "Search '${1}' on Google\0icon\x1f${ICON_DIR}/google.svg\x1finfo\x1fgoogle"
        echo -e "Search '${1}' on YouTube\0icon\x1f${ICON_DIR}/youtube.svg\x1finfo\x1fyoutube"
    fi
fi
