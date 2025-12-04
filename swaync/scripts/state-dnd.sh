#!/usr/bin/env bash
if swaync-client --get-dnd 2>/dev/null | grep -qi "true\|enabled\|on"; then
  echo true
else
  echo false
fi

