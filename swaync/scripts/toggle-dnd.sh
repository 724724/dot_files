#!/usr/bin/env bash
if [[ "$SWAYNC_TOGGLE_STATE" == "true" ]]; then
  swaync-client --dnd-on
else
  swaync-client --dnd-off
fi

