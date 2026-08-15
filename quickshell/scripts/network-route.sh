#!/usr/bin/env bash

set -u

is_iphone_usb() {
    local driver
    driver=$(readlink -f "/sys/class/net/$1/device/driver" 2>/dev/null || true)
    [[ ${driver##*/} == ipheth ]]
}

CONNECTED_WIFI=()
CONNECTED_ETHERNET=()

collect_connected_devices() {
    local device type state
    CONNECTED_WIFI=()
    CONNECTED_ETHERNET=()
    while IFS=: read -r device type state; do
        [[ $state == connected ]] || continue
        case $type in
            wifi)
                CONNECTED_WIFI+=("$device")
                ;;
            ethernet)
                is_iphone_usb "$device" || CONNECTED_ETHERNET+=("$device")
                ;;
        esac
    done < <(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null)
}

default_device() {
    local family i
    local -a route=()
    for family in 4 6; do
        route=()
        if [[ $family == 4 ]]; then
            read -r -a route < <(ip -4 route get 1.1.1.1 2>/dev/null)
        else
            read -r -a route < <(ip -6 route get 2606:4700:4700::1111 2>/dev/null)
        fi
        for ((i = 0; i + 1 < ${#route[@]}; i++)); do
            if [[ ${route[i]} == dev ]]; then
                printf '%s' "${route[i + 1]}"
                return
            fi
        done
    done
}

connection_name() {
    local name=""
    IFS= read -r name < <(nmcli -g GENERAL.CONNECTION device show "$1" 2>/dev/null)
    printf '%s' "$name"
}

connection_uuid() {
    local uuid=""
    IFS= read -r uuid < <(nmcli -g GENERAL.CON-UUID device show "$1" 2>/dev/null)
    printf '%s' "$uuid"
}

set_metric() {
    local device=$1 metric=$2 uuid
    uuid=$(connection_uuid "$device")
    [[ -n $uuid && $uuid != -- ]] || return
    nmcli connection modify uuid "$uuid" \
        ipv4.never-default no ipv6.never-default no \
        ipv4.route-metric "$metric" ipv6.route-metric "$metric" >/dev/null 2>&1
}

reapply() {
    local device=$1 uuid
    nmcli device reapply "$device" >/dev/null 2>&1 && return
    uuid=$(connection_uuid "$device")
    [[ -n $uuid && $uuid != -- ]] &&
        nmcli connection up uuid "$uuid" ifname "$device" >/dev/null 2>&1
}

status() {
    local default_dev wifi_dev="" ethernet_dev="" kind=none ssid=""
    collect_connected_devices
    default_dev=$(default_device)
    ((${#CONNECTED_WIFI[@]})) && wifi_dev=${CONNECTED_WIFI[0]}
    ((${#CONNECTED_ETHERNET[@]})) && ethernet_dev=${CONNECTED_ETHERNET[0]}

    for device in "${CONNECTED_WIFI[@]}"; do
        if [[ $device == "$default_dev" ]]; then
            kind=wifi
            wifi_dev=$device
            break
        fi
    done
    if [[ $kind != wifi ]]; then
        for device in "${CONNECTED_ETHERNET[@]}"; do
            if [[ $device == "$default_dev" ]]; then
                kind=ethernet
                ethernet_dev=$device
                break
            fi
        done
    fi

    [[ -n $wifi_dev ]] && ssid=$(connection_name "$wifi_dev")
    printf '%s|%s|%s|%s\n' \
        "$([[ $(nmcli radio wifi 2>/dev/null) == enabled ]] && printf on || printf off)" \
        "$ssid" "$kind" "$([[ -n $ethernet_dev ]] && printf yes || printf no)"
}

bar_status() {
    local device type connection
    local -a details=()
    device=$(default_device)
    if [[ -z $device ]]; then
        printf 'none||\n'
        return
    fi
    mapfile -t details < <(nmcli -g GENERAL.TYPE,GENERAL.CONNECTION device show "$device" 2>/dev/null)
    type=${details[0]:-}
    connection=${details[1]:-}
    [[ $type == ethernet ]] && is_iphone_usb "$device" && type=iphone
    printf '%s|%s|%s\n' "$type" "$connection" "$device"
}

prefer_wifi() {
    collect_connected_devices
    ((${#CONNECTED_WIFI[@]})) || return 1
    for device in "${CONNECTED_ETHERNET[@]}"; do set_metric "$device" 600; done
    for device in "${CONNECTED_WIFI[@]}"; do set_metric "$device" 50; done
    for device in "${CONNECTED_ETHERNET[@]}"; do reapply "$device"; done
    for device in "${CONNECTED_WIFI[@]}"; do reapply "$device"; done
}

prefer_ethernet() {
    local target device
    collect_connected_devices
    ((${#CONNECTED_ETHERNET[@]})) || return 1
    target=${CONNECTED_ETHERNET[0]}
    for device in "${CONNECTED_WIFI[@]}"; do set_metric "$device" 600; done
    for device in "${CONNECTED_ETHERNET[@]}"; do
        [[ $device == "$target" ]] && set_metric "$device" 50 || set_metric "$device" 600
    done
    for device in "${CONNECTED_WIFI[@]}"; do reapply "$device"; done
    for device in "${CONNECTED_ETHERNET[@]}"; do reapply "$device"; done
}

case ${1:-status} in
    status) status ;;
    bar-status) bar_status ;;
    prefer-wifi) prefer_wifi ;;
    prefer-ethernet) prefer_ethernet ;;
    *) exit 2 ;;
esac
