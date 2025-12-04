#!/usr/bin/env bash
if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
  echo true
else
  echo false
fi

