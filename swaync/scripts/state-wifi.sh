#!/usr/bin/env bash
if [[ "$(nmcli radio wifi)" == "enabled" ]]; then
  echo true
else
  echo false
fi

