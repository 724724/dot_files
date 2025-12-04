#!/usr/bin/env bash
if [[ "$SWAYNC_TOGGLE_STATE" == "true" ]]; then
  nmcli radio all off
  bluetoothctl power off >/dev/null 2>&1
else
  nmcli radio all on
  bluetoothctl power on >/dev/null 2>&1
fi

