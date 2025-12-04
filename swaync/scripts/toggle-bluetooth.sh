#!/usr/bin/env bash
if [[ "$SWAYNC_TOGGLE_STATE" == "true" ]]; then
  bluetoothctl power on >/dev/null 2>&1
else
  bluetoothctl power off >/dev/null 2>&1
fi

