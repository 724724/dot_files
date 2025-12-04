#!/usr/bin/env bash
wifi_state="$(nmcli radio wifi 2>/dev/null)"
bt_state="$(bluetoothctl show 2>/dev/null | awk '/Powered:/ {print $2}')"

if [[ "$wifi_state" == "disabled" && "$bt_state" == "no" ]]; then
  echo true   # 비행기 모드 ON
else
  echo false  # 비행기 모드 OFF
fi

